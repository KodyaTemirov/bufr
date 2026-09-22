import AppKit
import HotKey

/// Persists hotkey bindings as JSON under a single UserDefaults key.
/// A missing action means "use the default"; an explicit null means "disabled by the user".
struct HotKeyBindingStore {
    static let storageKey = "hotKeys"

    let defaults: UserDefaults

    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        if let stored = load()[action.rawValue] {
            return stored
        }
        return action.defaultBinding
    }

    func save(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        var all = load()
        all[action.rawValue] = .some(binding) // keeps an explicit nil ("disabled")
        write(all)
    }

    func reset(_ action: HotKeyAction) {
        var all = load()
        all.removeValue(forKey: action.rawValue)
        write(all)
    }

    /// Converts the pre-3.0 `hotKeyCode` / `hotKeyModifiers` (raw NSEvent flags) into the
    /// panel binding, then removes the old keys.
    func migrateLegacyIfNeeded() {
        guard let code = defaults.object(forKey: "hotKeyCode") as? Int else { return }

        if load()[HotKeyAction.togglePanel.rawValue] == nil {
            let rawFlags = UInt(defaults.integer(forKey: "hotKeyModifiers"))
            let modifiers = NSEvent.ModifierFlags(rawValue: rawFlags)
                .intersection(HotKeyBinding.relevantModifiers)
            save(
                HotKeyBinding(carbonKeyCode: UInt32(code), carbonModifiers: modifiers.carbonFlags),
                for: .togglePanel
            )
        }
        defaults.removeObject(forKey: "hotKeyCode")
        defaults.removeObject(forKey: "hotKeyModifiers")
    }

    // MARK: - Private

    private func load() -> [String: HotKeyBinding?] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: HotKeyBinding?].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ all: [String: HotKeyBinding?]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
