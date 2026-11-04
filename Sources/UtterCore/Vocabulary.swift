import Foundation

/// A word or name you use that speech recognition tends to get wrong.
public struct VocabularyEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// How it should be written, e.g. "Leitro".
    public var term: String
    /// What the recognizer produces instead, e.g. ["light row", "lei tro"].
    public var soundsLike: [String]

    public init(id: UUID = UUID(), term: String, soundsLike: [String] = []) {
        self.id = id
        self.term = term
        self.soundsLike = soundsLike
    }
}

/// Personal vocabulary: biases recognition toward your terms, fixes known
/// mishearings, and tells the cleanup model how to spell them.
public struct Vocabulary: Codable, Equatable, Sendable {
    public var entries: [VocabularyEntry]

    public init(entries: [VocabularyEntry] = []) {
        self.entries = entries
    }

    /// Unique, non-empty terms in the order they were added.
    public var terms: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }
    }

    /// Rewrites known mishearings to the preferred spelling and fixes the
    /// capitalization of terms that aren't all lowercase ("leitro" → "Leitro").
    /// Matches whole words, ignores case and treats any run of spaces alike.
    /// Longer phrases are replaced first.
    public func apply(to text: String) -> String {
        var rules: [(pattern: String, term: String)] = []
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            for spoken in entry.soundsLike {
                let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !spoken.isEmpty { rules.append((spoken, term)) }
            }
            if term != term.lowercased() { rules.append((term, term)) }
        }
        rules.sort { $0.pattern.count > $1.pattern.count }

        var result = text
        for rule in rules {
            guard let regex = Self.wholeWordRegex(rule.pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: rule.term))
        }
        return result
    }

    private static func wholeWordRegex(_ phrase: String) -> NSRegularExpression? {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return nil }
        let body = words.joined(separator: "\\s+")
        return try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
    }
}
