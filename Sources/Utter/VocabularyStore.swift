import AppKit
import UtterCore

/// Keeps your personal vocabulary in a plain JSON file you can read, back up
/// and edit: ~/Library/Application Support/Utter/vocabulary.json
@MainActor
final class VocabularyStore: ObservableObject {
    @Published var vocabulary: Vocabulary {
        didSet { if vocabulary != oldValue { save() } }
    }

    nonisolated static var fileURL: URL {
        AppPaths.supportDirectory.appending(path: "vocabulary.json")
    }

    init() {
        vocabulary = Self.load()
    }

    func add() {
        vocabulary.entries.append(VocabularyEntry(term: "", soundsLike: []))
    }

    func remove(_ id: VocabularyEntry.ID) {
        vocabulary.entries.removeAll { $0.id == id }
    }

    func revealInFinder() {
        save()
        NSWorkspace.shared.activateFileViewerSelecting([Self.fileURL])
    }

    nonisolated static func load() -> Vocabulary {
        guard let data = try? Data(contentsOf: fileURL) else { return Vocabulary() }
        do {
            return try JSONDecoder().decode(Vocabulary.self, from: data)
        } catch {
            NSLog("Utter: couldn't read vocabulary.json: \(error.localizedDescription)")
            return Vocabulary()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(vocabulary).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Utter: couldn't save vocabulary.json: \(error.localizedDescription)")
        }
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Utter")
    }

    static var modelsDirectory: URL {
        supportDirectory.appending(path: "Models")
    }
}
