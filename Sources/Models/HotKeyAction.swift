import AppKit
import HotKey

/// Every global shortcut Bufr can register, in Settings order.
enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case togglePanel
    case captureArea
    case captureWindow
    case captureFullscreen
    case capturePreviousArea
    case captureAllInOne
    case captureText
    case captureScrolling

    enum Group: CaseIterable {
        case panel
        case screenshots
    }

    var group: Group {
        switch self {
        case .togglePanel: .panel
        case .captureArea, .captureWindow, .captureFullscreen, .capturePreviousArea, .captureAllInOne, .captureText, .captureScrolling: .screenshots
        }
    }

    var defaultBinding: HotKeyBinding? {
        switch self {
        case .togglePanel: HotKeyBinding(key: .v, modifiers: [.command, .shift])
        case .captureArea: HotKeyBinding(key: .four, modifiers: [.command, .shift])
        case .captureFullscreen: HotKeyBinding(key: .three, modifiers: [.command, .shift])
        case .captureAllInOne: HotKeyBinding(key: .five, modifiers: [.command, .shift])
        case .captureText: HotKeyBinding(key: .two, modifiers: [.command, .shift])
        case .captureScrolling: HotKeyBinding(key: .four, modifiers: [.command, .shift, .option])
        case .captureWindow, .capturePreviousArea: nil
        }
    }

    /// Localization key of the action's name in Settings
    var titleKey: String { "hotkeys.action.\(rawValue)" }
}
