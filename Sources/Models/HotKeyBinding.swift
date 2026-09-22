import AppKit
import HotKey
import SwiftUI

/// A global shortcut, stored as Carbon codes so it is independent of NSEvent flag noise.
struct HotKeyBinding: Codable, Hashable, Sendable {
    var carbonKeyCode: UInt32
    var carbonModifiers: UInt32

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    init(key: Key, modifiers: NSEvent.ModifierFlags) {
        self.carbonKeyCode = key.carbonKeyCode
        self.carbonModifiers = modifiers.intersection(Self.relevantModifiers).carbonFlags
    }

    var key: Key? { Key(carbonKeyCode: carbonKeyCode) }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(carbonFlags: carbonModifiers) }

    var keyCombo: KeyCombo { KeyCombo(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers) }

    /// "⇧⌘V" — standard macOS order ⌃⌥⇧⌘
    var displayString: String {
        Self.modifierSymbols(modifiers) + (key?.description.uppercased() ?? "?")
    }

    static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Shortcut shown next to menu items; nil for keys without a letter or digit equivalent.
    var keyboardShortcut: KeyboardShortcut? {
        guard let description = key?.description, description.count == 1,
              let character = description.lowercased().first,
              character.isLetter || character.isNumber
        else { return nil }

        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
    }
}
