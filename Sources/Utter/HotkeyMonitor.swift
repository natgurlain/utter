import AppKit

/// Watches the trigger key system-wide. Global event monitors need the
/// Accessibility permission; they observe events and never swallow them.
@MainActor
final class HotkeyMonitor {
    var key: TriggerKey
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// Another key, modifier or click while the trigger key is held.
    var onInterrupt: () -> Void = {}
    var onEscape: () -> Void = {}

    private var monitors: [Any] = []
    private var isHeld = false

    private static let escapeKeyCode: UInt16 = 53

    init(key: TriggerKey) {
        self.key = key
    }

    func start() {
        stop()
        add(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.flagsChanged(event)
        })
        add(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.flagsChanged(event)
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.keyDown(event)
        })
        add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.keyDown(event)
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            guard let self, self.isHeld else { return }
            self.onInterrupt()
        })
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isHeld = false
    }

    private func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    private func flagsChanged(_ event: NSEvent) {
        guard event.keyCode == key.keyCode else {
            if isHeld { onInterrupt() }
            return
        }
        let down = key.isDown(event.modifierFlags)
        guard down != isHeld else { return }
        isHeld = down
        down ? onPress() : onRelease()
    }

    private func keyDown(_ event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onEscape()
        } else if isHeld {
            onInterrupt()
        }
    }
}
