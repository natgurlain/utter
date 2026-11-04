import SwiftUI

struct UtterApp: App {
    @StateObject private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                controller: controller,
                settings: controller.settings,
                permissions: controller.permissions,
                launchAtLogin: controller.launchAtLogin)
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: Permissions
    @ObservedObject var launchAtLogin: LaunchAtLogin

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Text(controller.statusText)

        if case .failed = controller.phase {
            Button("Try Again") { controller.retry() }
        }
        if !permissions.accessibility {
            Button("Grant Accessibility (to type into apps)…") { permissions.openAccessibilitySettings() }
            Button("Already Granted? Relaunch Utter") { permissions.relaunch() }
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

        if launchAtLogin.isInstalled {
            Toggle(
                "Launch at Login",
                isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
            if launchAtLogin.needsApproval {
                Button("Approve in Login Items…") { launchAtLogin.openLoginItemsSettings() }
            }
        } else {
            Text("Launch at Login: install to Applications first")
        }

        Divider()

        Text("Tap the key for hands-free · Esc cancels")
        Text("Speech stays on this Mac and is never saved")

        Divider()

        Button("Quit Utter \(version)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
