import AppKit
import HotKey

/// Every global shortcut Bufr can register. Capture actions are added in M1.
enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case togglePanel

    var defaultBinding: HotKeyBinding? {
        switch self {
        case .togglePanel: HotKeyBinding(key: .v, modifiers: [.command, .shift])
        }
    }

    /// Localization key of the action's name in Settings
    var titleKey: String { "hotkeys.action.\(rawValue)" }
}
