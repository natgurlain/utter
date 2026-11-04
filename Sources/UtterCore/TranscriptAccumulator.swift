import Foundation

/// Assembles streaming recognizer output: finalized segments plus the current
/// volatile (still-changing) guess.
public struct TranscriptAccumulator: Sendable {
    public private(set) var finalized = ""
    public private(set) var volatile = ""

    public init() {}

    public mutating func apply(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized = Self.join(finalized, text)
            volatile = ""
        } else {
            volatile = text
        }
    }

    /// What to show while the user is still talking.
    public var display: String {
        Self.join(finalized, volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text to insert once recognition has finished.
    public var result: String {
        finalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last else { return tail }
        guard let first = tail.first else { return head }
        if last.isWhitespace || first.isWhitespace || ",.!?;:)".contains(first) {
            return head + tail
        }
        return head + " " + tail
    }
}
