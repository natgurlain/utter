import Foundation
import FoundationModels
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import UtterCore

/// Which on-device model tidies the transcript for the current language.
enum CleanupEngine: Equatable {
    case apple
    case local(URL)
}

/// Apple's on-device model (Apple Intelligence). No download, ~20 languages.
enum AppleCleanup {
    static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    static func supports(_ locale: Locale) -> Bool {
        guard case .available = model.availability else { return false }
        return model.supportsLocale(locale)
    }

    /// Why the Apple model can't be used at all, or nil when it's available.
    static var unavailableReason: String? {
        switch model.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is turned off"
        case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence"
        case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading"
        case .unavailable: return "Apple Intelligence is unavailable"
        }
    }

    static func clean(_ text: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0))
        return response.content
    }
}

/// An open model run locally with MLX, loaded from
/// ~/Library/Application Support/Utter/Models/<name>/ (see scripts/download-model.sh).
/// Kept in memory once loaded so later dictations are fast.
///
/// The instructions are the same for every request, so they're run through the
/// model once and their KV cache is kept. Each request starts from a copy of
/// that cache and only processes the dictated text, which takes the prompt
/// step from seconds to a fraction of a second.
actor LocalCleanup {
    static let shared = LocalCleanup()

    private var container: ModelContainer?
    private var loadedURL: URL?
    private var prefix: PromptPrefix?

    private static let parameters = GenerateParameters(maxTokens: 1024, temperature: 0)

    /// Model folders that contain a config and weights.
    nonisolated static func installedModels() -> [URL] {
        let fileManager = FileManager.default
        let folders =
            (try? fileManager.contentsOfDirectory(
                at: AppPaths.modelsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.filter { folder in
            let files = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            return files.contains("config.json") && files.contains { $0.hasSuffix(".safetensors") }
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Loads the model and, given the instructions, caches them and runs one
    /// short cleanup so the GPU kernels are compiled before the first dictation.
    func preload(_ url: URL, instructions: String? = nil) async {
        do {
            _ = try await load(url)
            if let instructions {
                _ = try await clean("um hello there", instructions: instructions, model: url)
            }
        } catch {
            NSLog("Utter: couldn't load cleanup model \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func unload() {
        container = nil
        loadedURL = nil
        prefix = nil
    }

    func clean(_ text: String, instructions: String, model url: URL) async throws -> String {
        let container = try await load(url)
        let cached = prefix?.instructions == instructions ? prefix : nil
        let (output, built) = try await container.perform { context -> (String, PromptPrefix?) in
            let prefix = try cached ?? PromptPrefix(instructions: instructions, context: context)
            let prompt = try PromptPrefix.render(user: text, instructions: instructions, tokenizer: context.tokenizer)

            // Continue from the cached instructions when the prompt starts with them.
            let input: LMInput
            let cache: [KVCache]?
            if let prefix, prompt.count > prefix.tokens.count, prompt.starts(with: prefix.tokens) {
                input = LMInput(tokens: MLXArray(Array(prompt[prefix.tokens.count...])))
                cache = prefix.cache.map { $0.copy() }
            } else {
                input = LMInput(tokens: MLXArray(prompt))
                cache = nil
            }

            var output = ""
            for await generation in try generate(input: input, cache: cache, parameters: Self.parameters, context: context) {
                if case .chunk(let chunk) = generation { output += chunk }
            }
            return (output, prefix)
        }
        if let built, built.instructions == instructions { prefix = built }
        return output
    }

    private func load(_ url: URL) async throws -> ModelContainer {
        if let container, loadedURL == url { return container }
        container = nil
        prefix = nil
        let loaded = try await LLMModelFactory.shared.loadContainer(from: url, using: TransformersTokenizerLoader())
        container = loaded
        loadedURL = url
        return loaded
    }
}

/// The instructions' tokens and the KV cache after running them through the model.
/// The cache is only read (copied) once built, so sharing it is safe.
private final class PromptPrefix: @unchecked Sendable {
    let instructions: String
    let tokens: [Int]
    let cache: [KVCache]

    /// Returns nil when the chat template doesn't give a stable prefix to cache.
    init?(instructions: String, context: ModelContext) throws {
        // The part of the prompt shared by any two user messages is the cacheable prefix.
        let a = try Self.render(user: "a", instructions: instructions, tokenizer: context.tokenizer)
        let b = try Self.render(user: "b", instructions: instructions, tokenizer: context.tokenizer)
        let length = zip(a, b).prefix { $0 == $1 }.count
        let cache = try context.model.newCache(parameters: nil)
        guard length > 0, canTrimPromptCache(cache) else { return nil }

        let tokens = Array(a.prefix(length))
        let text = LMInput.Text(tokens: MLXArray(tokens))
        _ = context.model(text[text: .newAxis], cache: cache, state: nil)
        eval(cache)

        self.instructions = instructions
        self.tokens = tokens
        self.cache = cache
    }

    static func render(user: String, instructions: String, tokenizer: any MLXLMCommon.Tokenizer) throws -> [Int] {
        try tokenizer.applyChatTemplate(messages: [
            ["role": "system", "content": instructions],
            ["role": "user", "content": user],
        ])
    }
}

/// Adapts swift-transformers' tokenizers to MLX (loading from a local folder only).
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

/// Runs vocabulary fixes and the cleanup model, falling back to the raw
/// transcript whenever cleanup is off, unavailable, slow or unfaithful.
enum PostProcessor {
    static let timeout: Duration = .seconds(10)

    struct Result {
        var text: String
        var cleanedBy: String?
    }

    static func process(
        _ raw: String, locale: Locale, vocabulary: Vocabulary, engine: CleanupEngine?
    ) async -> Result {
        let corrected = vocabulary.apply(to: raw)
        guard let engine, CleanupGuard.words(corrected).count >= 2 else {
            return Result(text: corrected, cleanedBy: nil)
        }

        let instructions = Self.instructions(locale: locale, vocabulary: vocabulary)
        do {
            let output = try await withTimeout(timeout) {
                switch engine {
                case .apple: return try await AppleCleanup.clean(corrected, instructions: instructions)
                case .local(let url):
                    return try await LocalCleanup.shared.clean(corrected, instructions: instructions, model: url)
                }
            }
            guard let accepted = CleanupGuard.accept(original: corrected, cleaned: output) else {
                NSLog("Utter: cleanup output rejected, using the raw transcript")
                return Result(text: corrected, cleanedBy: nil)
            }
            return Result(text: vocabulary.apply(to: accepted), cleanedBy: engine.label)
        } catch {
            NSLog("Utter: cleanup failed, using the raw transcript: \(error.localizedDescription)")
            return Result(text: corrected, cleanedBy: nil)
        }
    }

    static func instructions(locale: Locale, vocabulary: Vocabulary) -> String {
        let languageName = Locale(identifier: "en").localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return CleanupPrompt.instructions(languageName: languageName, terms: vocabulary.terms)
    }

    private struct TimedOut: Error {}

    private static func withTimeout<T: Sendable>(
        _ limit: Duration, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}

extension CleanupEngine {
    var label: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .local(let url): return url.lastPathComponent
        }
    }
}
