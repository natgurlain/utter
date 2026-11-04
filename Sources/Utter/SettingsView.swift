import AppKit
import SwiftUI
import UtterCore

struct SettingsView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        TabView {
            VocabularyTab(store: controller.vocabulary)
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            CleanupTab(controller: controller, settings: controller.settings)
                .tabItem { Label("Cleanup", systemImage: "sparkles") }
        }
        .frame(width: 600, height: 460)
        .onAppear { controller.refreshModels() }
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject var store: VocabularyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Names and jargon Utter should get right. Recognition is nudged toward these terms, known mishearings are replaced, and the cleanup model is told how to spell them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Write it as").frame(width: 170, alignment: .leading)
                Text("Often heard as (comma-separated, optional)")
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            List {
                ForEach($store.vocabulary.entries) { $entry in
                    VocabularyRow(entry: $entry) { store.remove(entry.id) }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if store.vocabulary.entries.isEmpty {
                    Text("No terms yet. Add names, products and jargon you dictate often.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    store.add()
                } label: {
                    Label("Add Term", systemImage: "plus")
                }
                Spacer()
                Button("Show File in Finder") { store.revealInFinder() }
            }
        }
        .padding(20)
    }
}

private struct VocabularyRow: View {
    @Binding var entry: VocabularyEntry
    let onDelete: () -> Void

    private var soundsLike: Binding<String> {
        Binding(
            get: { entry.soundsLike.joined(separator: ", ") },
            set: { entry.soundsLike = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("e.g. Leitro", text: $entry.term)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            TextField("e.g. light row, lei tro", text: soundsLike)
                .textFieldStyle(.roundedBorder)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this term")
            .accessibilityLabel("Remove \(entry.term)")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Cleanup

private struct CleanupTab: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Tidy up text after dictating", isOn: $settings.cleanupEnabled)
                Text("Adds punctuation and capitals and removes filler words with a language model running on this Mac. If the result doesn't match what you said, or takes over 10 seconds, Utter inserts the plain transcript instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Right now") {
                    Text(controller.cleanupStatus)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Apple Intelligence") {
                LabeledContent("Status") {
                    Text(AppleCleanup.unavailableReason ?? "Available")
                }
                Toggle("Prefer Apple Intelligence when it supports the language", isOn: $settings.preferAppleModel)
                    .disabled(!settings.cleanupEnabled)
                Text("No download needed. Covers English, German, French, Spanish, Italian, Portuguese, Japanese, Chinese and others, but not Polish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Local model") {
                if controller.installedModels.isEmpty {
                    Text("No local model installed. From the Utter folder run:")
                        .foregroundStyle(.secondary)
                    Text("scripts/download-model.sh")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                } else {
                    Picker("Model", selection: $settings.localModelName) {
                        ForEach(controller.installedModels, id: \.lastPathComponent) { url in
                            Text(url.lastPathComponent).tag(url.lastPathComponent)
                        }
                    }
                    .disabled(!settings.cleanupEnabled)
                }
                Text("An open model run with MLX on this Mac. It covers languages Apple's model doesn't, such as Polish, and stays in memory (about 2.5 GB) while Utter runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Models Folder") {
                        try? FileManager.default.createDirectory(
                            at: AppPaths.modelsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppPaths.modelsDirectory)
                    }
                    Button("Refresh") { controller.refreshModels() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if settings.localModelName.isEmpty, let first = controller.installedModels.first {
                settings.localModelName = first.lastPathComponent
            }
        }
    }
}
