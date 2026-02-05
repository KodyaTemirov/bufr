import AppKit
import HotKey

@MainActor @Observable
final class HotKeyManager {
    private var hotKey: HotKey?
    var onTogglePanel: (() -> Void)?

    func register(key: Key = .v, modifiers: NSEvent.ModifierFlags = [.command, .shift]) {
        unregister()
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onTogglePanel?()
            }
        }
    }

    func unregister() {
        hotKey = nil
    }
}
