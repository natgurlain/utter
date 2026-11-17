import Foundation

/// Groups finalized recognizer segments into chunks worth tidying on their own,
/// so cleanup can run while the user is still talking.
///
/// A chunk is sent once it ends a sentence and has a few words (so the model
/// has context and fillers aren't left alone), or once it gets long.
public struct LiveChunker: Sendable {
    public let minWords: Int
    public let maxWords: Int
    public private(set) var pending = ""

    public init(minWords: Int = 3, maxWords: Int = 30) {
        self.minWords = minWords
        self.maxWords = maxWords
    }

    /// Adds a finalized segment; returns a chunk when one is ready.
    public mutating func add(_ segment: String) -> String? {
        pending = TranscriptAccumulator.join(pending, segment)
        let words = CleanupGuard.words(pending).count
        guard words >= maxWords || (words >= minWords && Self.endsSentence(pending)) else { return nil }
        return flush()
    }

    /// Whatever is left, e.g. when the user lets go of the key.
    public mutating func flush() -> String? {
        let chunk = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return chunk.isEmpty ? nil : chunk
    }

    public static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?…。！？".contains(last)
    }
}

/// Joins chunks that were tidied separately back into one text.
public enum ChunkStitcher {
    /// - Parameter pieces: each chunk as spoken and as tidied, in order.
    public static func stitch(_ pieces: [(raw: String, cleaned: String)]) -> String {
        var text = ""
        for (index, piece) in pieces.enumerated() {
            var cleaned = piece.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            let isLast = index == pieces.count - 1
            let continues = !LiveChunker.endsSentence(piece.raw) && !isLast

            // The chunk was cut mid-sentence: the model doesn't know the sentence
            // goes on, so undo a full stop it added at the end…
            if continues, cleaned.hasSuffix("."), !cleaned.hasSuffix("...") { cleaned.removeLast() }
            // …and the capital it gave the next chunk's first word.
            if index > 0, !LiveChunker.endsSentence(pieces[index - 1].raw),
                let spoken = piece.raw.first(where: \.isLetter), spoken.isLowercase,
                let first = cleaned.first, first.isUppercase, first.lowercased() == String(spoken)
            {
                cleaned = first.lowercased() + cleaned.dropFirst()
            }
            text = TranscriptAccumulator.join(text, cleaned)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
