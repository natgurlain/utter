import Foundation

public enum LocaleResolver {
    /// Picks a supported BCP-47 identifier for the requested one.
    ///
    /// Exact match first, then the same language (preferring the user's region,
    /// then `<lang>-US`, then alphabetical), then `en-US`.
    public static func resolve(_ requested: String, supported: Set<String>, preferredRegion: String?) -> String? {
        if supported.contains(requested) { return requested }
        let language = Locale(identifier: requested).language.languageCode?.identifier
        if let language {
            let sameLanguage = supported
                .filter { Locale(identifier: $0).language.languageCode?.identifier == language }
                .sorted()
            if let region = preferredRegion, let match = sameLanguage.first(where: { $0.hasSuffix("-\(region)") }) {
                return match
            }
            if let us = sameLanguage.first(where: { $0.hasSuffix("-US") }) { return us }
            if let first = sameLanguage.first { return first }
        }
        return supported.contains("en-US") ? "en-US" : supported.sorted().first
    }
}
