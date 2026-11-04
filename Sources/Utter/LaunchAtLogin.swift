import AppKit
import ServiceManagement

/// Starts Utter when you log in, using the system login-item service.
///
/// Only offered when Utter runs from an Applications folder: a login item
/// pointing at a build folder breaks as soon as that folder moves, and macOS
/// privacy permissions are most reliable for an app at a stable location.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status

    private static let enabledOnceKey = "launchAtLoginEnabledOnce"

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    var isInstalled: Bool {
        let path = Bundle.main.bundleURL.deletingLastPathComponent().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
        return path == "/Applications" || path == userApplications
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled, status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Utter: couldn't update launch at login: \(error.localizedDescription)")
        }
        refresh()
    }

    /// Turn it on the first time an installed copy runs; respect the user's choice afterwards.
    func enableOnFirstInstalledLaunch() {
        let defaults = UserDefaults.standard
        guard isInstalled, !defaults.bool(forKey: Self.enabledOnceKey) else { return }
        defaults.set(true, forKey: Self.enabledOnceKey)
        setEnabled(true)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
