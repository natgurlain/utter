import Foundation
import UtterCore

/// Entry point. Without arguments Utter starts the menu bar app.
///
/// Headless modes for testing without a microphone (they use your saved
/// vocabulary unless `--vocabulary <file.json>` is given):
///
///     Utter --transcribe <audio-file> [--locale pl-PL] [--engine auto|apple|local|none] [--vocabulary <file>]
///     Utter --clean "<text>"          [--locale pl-PL] [--engine auto|apple|local|none] [--vocabulary <file>]
///
/// The raw transcript goes to stderr, the final text to stdout.
@main
enum Main {
    @MainActor
    static func main() async {
        let arguments = CommandLine.arguments
        let audio = value(after: "--transcribe", in: arguments)
        let text = value(after: "--clean", in: arguments)
        guard audio != nil || text != nil else {
            UtterApp.main()
            return
        }

        let localeID = value(after: "--locale", in: arguments) ?? Locale.current.identifier(.bcp47)
        let engineName = value(after: "--engine", in: arguments) ?? "auto"
        let vocabulary = value(after: "--vocabulary", in: arguments).map(loadVocabulary) ?? VocabularyStore.load()

        do {
            let transcriber = Transcriber()
            transcriber.contextualStrings = vocabulary.terms
            let resolved = try await transcriber.prepare(localeID: localeID)
            let locale = Locale(identifier: resolved)

            let raw: String
            if let audio {
                raw = try await transcriber.transcribe(file: URL(fileURLWithPath: audio))
            } else {
                raw = text ?? ""
            }
            log("language: \(resolved)")
            log("raw:      \(raw)")

            let engine = pickEngine(engineName, locale: locale)
            log("cleanup:  \(engine?.label ?? "none")")
            if case .local(let url) = engine {
                // The app keeps the model loaded; time loading separately from cleanup.
                let loadStart = Date()
                await LocalCleanup.shared.preload(url)
                log(String(format: "load:     %.2fs", Date().timeIntervalSince(loadStart)))
            }
            let start = Date()
            let result = await PostProcessor.process(raw, locale: locale, vocabulary: vocabulary, engine: engine)
            log(String(format: "time:     %.2fs%@", Date().timeIntervalSince(start), result.cleanedBy == nil ? " (raw kept)" : ""))
            print(result.text)
            exit(0)
        } catch {
            log("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func pickEngine(_ name: String, locale: Locale) -> CleanupEngine? {
        let local = LocalCleanup.installedModels().first.map(CleanupEngine.local)
        switch name {
        case "none": return nil
        case "apple": return .apple
        case "local": return local
        default: return AppleCleanup.supports(locale) ? .apple : local
        }
    }

    private static func loadVocabulary(_ path: String) -> Vocabulary {
        guard let data = FileManager.default.contents(atPath: path),
            let vocabulary = try? JSONDecoder().decode(Vocabulary.self, from: data)
        else {
            log("couldn't read vocabulary file \(path)")
            exit(1)
        }
        return vocabulary
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("Utter: \(message)\n".utf8))
    }
}
