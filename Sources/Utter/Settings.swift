import AppKit
import Combine

/// The modifier key you hold to talk. Left and right keys are told apart
/// with device-specific flag bits, so the left ⌘/⌥ keep working as usual.
enum TriggerKey: String, CaseIterable, Identifiable {
    case rightCommand
    case rightOption
    case function

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightCommand: return "Right ⌘ Command"
        case .rightOption: return "Right ⌥ Option"
        case .function: return "Fn / Globe"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .function: return 63
        }
    }

    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .rightCommand: return flags.rawValue & 0x10 != 0  // NX_DEVICERCMDKEYMASK
        case .rightOption: return flags.rawValue & 0x40 != 0  // NX_DEVICERALTKEYMASK
        case .function: return flags.contains(.function)
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var triggerKey: TriggerKey {
        didSet { defaults.set(triggerKey.rawValue, forKey: Keys.triggerKey) }
    }

    /// BCP-47 identifier of the dictation language, e.g. "pl-PL".
    @Published var localeID: String {
        didSet { defaults.set(localeID, forKey: Keys.localeID) }
    }

    /// Put back whatever was on the clipboard after pasting the dictated text.
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) }
    }

    /// Append a space so consecutive dictations don't run together.
    @Published var addTrailingSpace: Bool {
        didSet { defaults.set(addTrailingSpace, forKey: Keys.addTrailingSpace) }
    }

    private enum Keys {
        static let triggerKey = "triggerKey"
        static let localeID = "localeID"
        static let restoreClipboard = "restoreClipboard"
        static let addTrailingSpace = "addTrailingSpace"
    }

    private init() {
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: Keys.triggerKey) ?? "") ?? .rightCommand
        localeID = defaults.string(forKey: Keys.localeID) ?? Locale.current.identifier(.bcp47)
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        addTrailingSpace = defaults.object(forKey: Keys.addTrailingSpace) as? Bool ?? true
    }
}
