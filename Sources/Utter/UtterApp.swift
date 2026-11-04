import SwiftUI

struct UtterApp: App {
    @StateObject private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller, settings: controller.settings, permissions: controller.permissions)
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: Permissions

    var body: some View {
        Text(controller.statusText)

        if case .failed = controller.phase {
            Button("Try Again") { controller.retry() }
        }
        if !permissions.accessibility {
            Button("Grant Accessibility (to type into apps)…") { permissions.openAccessibilitySettings() }
        }
        if permissions.microphone != .authorized {
            Button("Grant Microphone Access…") { permissions.openMicrophoneSettings() }
        }

        Divider()

        Picker("Language", selection: $settings.localeID) {
            ForEach(controller.languages) { language in
                Text(language.name).tag(language.id)
            }
        }
        .disabled(controller.isBusy)

        Picker("Hold to Talk", selection: $settings.triggerKey) {
            ForEach(TriggerKey.allCases) { key in
                Text(key.label).tag(key)
            }
        }

        Toggle("Restore Clipboard After Inserting", isOn: $settings.restoreClipboard)
        Toggle("Add Space After Text", isOn: $settings.addTrailingSpace)

        Divider()

        Text("Tap the key for hands-free · Esc cancels")
        Text("Speech is processed on this Mac and never saved")

        Divider()

        Button("Quit Utter") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
