import AppKit
import HotKey

/// Reads which macOS screenshot shortcuts are active, so Bufr never registers the same combo
/// (which one would win is undefined — a double capture or none).
enum SystemShortcutInspector {
    /// IDs in com.apple.symbolichotkeys and their factory combos:
    /// 28 ⇧⌘3 save screen, 29 ⌃⇧⌘3 copy screen, 30 ⇧⌘4 save area, 31 ⌃⇧⌘4 copy area, 184 ⇧⌘5 options
    static let screenshotDefaults: [Int: HotKeyBinding] = [
        28: HotKeyBinding(key: .three, modifiers: [.command, .shift]),
        29: HotKeyBinding(key: .three, modifiers: [.command, .shift, .control]),
        30: HotKeyBinding(key: .four, modifiers: [.command, .shift]),
        31: HotKeyBinding(key: .four, modifiers: [.command, .shift, .control]),
        184: HotKeyBinding(key: .five, modifiers: [.command, .shift]),
    ]

    /// No key code in the plist ("parameters" of a shortcut without a key)
    private static let noKeyCode = 65535

    static func enabledScreenshotShortcuts() -> Set<HotKeyBinding> {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return enabledScreenshotShortcuts(in: hotKeys)
    }

    /// A missing ID means macOS uses its default: the shortcut is enabled with the factory combo.
    static func enabledScreenshotShortcuts(in symbolicHotKeys: [String: Any]?) -> Set<HotKeyBinding> {
        var enabled = Set<HotKeyBinding>()
        for (id, factoryCombo) in screenshotDefaults {
            guard let entry = symbolicHotKeys?[String(id)] as? [String: Any] else {
                enabled.insert(factoryCombo)
                continue
            }
            guard isEnabled(entry["enabled"]) else { continue }

            if let value = entry["value"] as? [String: Any],
               let parameters = value["parameters"] as? [Int],
               parameters.count >= 3,
               parameters[1] != noKeyCode {
                let modifiers = NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))
                    .intersection(HotKeyBinding.relevantModifiers)
                enabled.insert(HotKeyBinding(carbonKeyCode: UInt32(parameters[1]), carbonModifiers: modifiers.carbonFlags))
            } else {
                enabled.insert(factoryCombo)
            }
        }
        return enabled
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? Int { return number != 0 }
        return true
    }
}
