@preconcurrency import AVFoundation
import Speech
import UtterCore

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum TranscriberError: LocalizedError {
    case notPrepared
    case unsupportedLocale(String)
    case noAudioFormat
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .notPrepared: return "The speech model isn't ready yet."
        case .unsupportedLocale(let id): return "On-device dictation doesn't support \(id)."
        case .noAudioFormat: return "Couldn't set up an audio format for the speech model."
        case .noInputDevice: return "No microphone is available."
        }
    }
}

/// Records from the microphone into memory and streams it to Apple's
/// on-device speech analyzer. Audio is never written to disk; buffers are
/// dropped as soon as the analyzer has consumed them.
///
/// Uses `SpeechTranscriber` (the newer long-form model) where the language
/// supports it, and `DictationTranscriber` (more languages, e.g. Polish)
/// otherwise.
@MainActor
final class Transcriber {
    private enum Engine {
        case speech
        case dictation
    }

    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    /// Names and terms from your vocabulary, passed to the recognizer as hints.
    var contextualStrings: [String] = []

    private(set) var locale: Locale?
    private var engine: Engine = .dictation
    private var analyzerFormat: AVAudioFormat?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerStart: Task<Void, Error>?
    private var collector: Task<String, Error>?

    static func languages() async -> [LanguageOption] {
        let ids = await allSupportedIDs()
        return ids
            .map { LanguageOption(id: $0, name: Locale.current.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Chooses the engine for the language and installs its on-device model
    /// (a one-time download that macOS performs; Utter itself has no network
    /// code). Returns the identifier actually used.
    func prepare(localeID: String) async throws -> String {
        let speechIDs = Set(await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })
        let allIDs = await Self.allSupportedIDs()
        guard
            let resolved = LocaleResolver.resolve(
                localeID, supported: allIDs, preferredRegion: Locale.current.region?.identifier)
        else { throw TranscriberError.unsupportedLocale(localeID) }

        let locale = Locale(identifier: resolved)
        let engine: Engine = speechIDs.contains(resolved) ? .speech : .dictation
        let module = Self.makeModule(engine, locale: locale)

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noAudioFormat
        }
        self.locale = locale
        self.engine = engine
        self.analyzerFormat = format
        return resolved
    }

    /// Starts capturing immediately; the analyzer catches up from the buffered stream.
    func start() throws {
        guard let locale, let analyzerFormat else { throw TranscriberError.notPrepared }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw TranscriberError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: hardwareFormat, to: analyzerFormat) else {
            throw TranscriberError.noAudioFormat
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let module = Self.makeModule(engine, locale: locale)
        let analyzer = SpeechAnalyzer(modules: [module])

        switch module {
        case let transcriber as SpeechTranscriber:
            collector = Task { try await self.collect(transcriber.results, text: { $0.text }, isFinal: { $0.isFinal }) }
        case let transcriber as DictationTranscriber:
            collector = Task { try await self.collect(transcriber.results, text: { $0.text }, isFinal: { $0.isFinal }) }
        default:
            break
        }

        self.analyzer = analyzer
        self.input = continuation
        let hints = contextualStrings
        analyzerStart = Task { try await Self.start(analyzer, input: stream, hints: hints) }

        inputNode.installTap(
            onBus: 0, bufferSize: 1024, format: hardwareFormat,
            block: Self.makeTap(converter: converter, format: analyzerFormat, input: continuation, level: onLevel))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            Task { await analyzer.cancelAndFinishNow() }
            reset()
            throw error
        }
    }

    /// Stops recording and returns the final transcript.
    func stop() async throws -> String {
        stopAudio()
        input?.finish()
        defer { reset() }
        try await analyzerStart?.value
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        return try await collector?.value ?? ""
    }

    func cancel() async {
        stopAudio()
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        collector?.cancel()
        reset()
    }

    /// Debug path: runs an audio file through the same conversion and
    /// recognition pipeline as the microphone. Used by `Utter --transcribe`.
    func transcribe(file url: URL) async throws -> String {
        guard let locale, let analyzerFormat else { throw TranscriberError.notPrepared }
        let file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: analyzerFormat) else {
            throw TranscriberError.noAudioFormat
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let module = Self.makeModule(engine, locale: locale)
        let analyzer = SpeechAnalyzer(modules: [module])
        let collector: Task<String, Error>
        switch module {
        case let transcriber as SpeechTranscriber:
            collector = Task { try await self.collect(transcriber.results, text: { $0.text }, isFinal: { $0.isFinal }) }
        case let transcriber as DictationTranscriber:
            collector = Task { try await self.collect(transcriber.results, text: { $0.text }, isFinal: { $0.isFinal }) }
        default:
            throw TranscriberError.notPrepared
        }
        try await Self.start(analyzer, input: stream, hints: contextualStrings)
        while file.framePosition < file.length,
            let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)
        {
            try file.read(into: chunk)
            if let converted = Self.convert(chunk, with: converter, to: analyzerFormat) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    // MARK: - Private

    /// Biases recognition toward your vocabulary, then starts analysis.
    private static func start(
        _ analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>, hints: [String]
    ) async throws {
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            do {
                try await analyzer.setContext(context)
            } catch {
                NSLog("Utter: couldn't apply vocabulary hints: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: input)
    }

    private static func allSupportedIDs() async -> Set<String> {
        let speech = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        return Set((speech + dictation).map { $0.identifier(.bcp47) })
    }

    private static func makeModule(_ engine: Engine, locale: Locale) -> any SpeechModule {
        switch engine {
        case .speech:
            return SpeechTranscriber(
                locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        case .dictation:
            return DictationTranscriber(
                locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults], attributeOptions: [])
        }
    }

    private func collect<Results: AsyncSequence>(
        _ results: Results,
        text: (Results.Element) -> AttributedString,
        isFinal: (Results.Element) -> Bool
    ) async throws -> String {
        var transcript = TranscriptAccumulator()
        for try await result in results {
            transcript.apply(String(text(result).characters), isFinal: isFinal(result))
            onPartial?(transcript.display)
        }
        return transcript.result
    }

    private func stopAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func reset() {
        analyzer = nil
        input = nil
        analyzerStart = nil
        collector = nil
    }

    /// Built outside the main actor: the tap runs on the real-time audio thread.
    nonisolated private static func makeTap(
        converter: AVAudioConverter,
        format: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        level: ((Float) -> Void)?
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            if let converted = convert(buffer, with: converter, to: format) {
                input.yield(AnalyzerInput(buffer: converted))
            }
            if let level {
                let value = normalizedLevel(buffer)
                DispatchQueue.main.async { level(value) }
            }
        }
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }

    /// RMS level mapped from -50…0 dB to 0…1 for the indicator.
    nonisolated private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
