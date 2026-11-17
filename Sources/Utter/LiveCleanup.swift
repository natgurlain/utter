import Foundation
import UtterCore

/// Tidies the transcript a sentence at a time while you're still talking, so
/// when you let go only the last sentence is left to clean up.
///
/// Chunks are cleaned one after another, in order. Each goes through the same
/// `PostProcessor` as before (vocabulary, model, guard, timeout), so a chunk the
/// model mangles or takes too long on falls back to its raw text on its own.
@MainActor
final class LiveCleanup {
    private struct Piece {
        let raw: String
        let task: Task<String, Never>
        var cleaned: String?
    }

    /// Called when a chunk has been tidied, to refresh the live text.
    var onChange: (() -> Void)?

    private let locale: Locale
    private let vocabulary: Vocabulary
    private let engine: CleanupEngine?
    private var chunker = LiveChunker()
    private var pieces: [Piece] = []
    private var previous: Task<String, Never>?

    init(locale: Locale, vocabulary: Vocabulary, engine: CleanupEngine?) {
        self.locale = locale
        self.vocabulary = vocabulary
        self.engine = engine
    }

    /// A segment the recognizer won't change any more.
    func add(final segment: String) {
        if let chunk = chunker.add(segment) { enqueue(chunk) }
    }

    /// True when the model still has (or will have) work to do in `finish()`.
    var hasPendingWork: Bool {
        engine != nil && (!chunker.pending.isEmpty || pieces.contains { $0.cleaned == nil })
    }

    /// Cleans what's left and returns the whole tidied text.
    func finish() async -> String {
        if let rest = chunker.flush() { enqueue(rest) }
        var done: [(raw: String, cleaned: String)] = []
        for piece in pieces { done.append((piece.raw, await piece.task.value)) }
        return vocabulary.apply(to: ChunkStitcher.stitch(done))
    }

    func cancel() {
        pieces.forEach { $0.task.cancel() }
        pieces.removeAll()
        previous = nil
        onChange = nil
    }

    /// Tidied sentences so far, followed by what's still raw.
    func display(volatile: String) -> String {
        let tidied = pieces.prefix { $0.cleaned != nil }
        var text = ChunkStitcher.stitch(tidied.map { ($0.raw, $0.cleaned ?? $0.raw) })
        for piece in pieces.dropFirst(tidied.count) { text = TranscriptAccumulator.join(text, piece.raw) }
        text = TranscriptAccumulator.join(text, chunker.pending)
        text = TranscriptAccumulator.join(text, volatile)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func enqueue(_ raw: String) {
        let previous = self.previous
        let (locale, vocabulary, engine) = (locale, vocabulary, engine)
        let task = Task {
            // One chunk at a time: the model is shared and order matters.
            _ = await previous?.value
            return await PostProcessor.process(raw, locale: locale, vocabulary: vocabulary, engine: engine).text
        }
        self.previous = task
        let index = pieces.count
        pieces.append(Piece(raw: raw, task: task))
        Task { [weak self] in
            let cleaned = await task.value
            guard let self, index < self.pieces.count, self.pieces[index].task == task else { return }
            self.pieces[index].cleaned = cleaned
            self.onChange?()
        }
    }
}
