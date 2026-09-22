import AppKit
import HotKey

/// Registers one Carbon hotkey per `HotKeyAction` and reports presses through `onAction`.
@MainActor @Observable
final class HotKeyManager {
    /// Current bindings; an action without an entry is disabled.
    private(set) var bindings: [HotKeyAction: HotKeyBinding] = [:]
    var onAction: ((HotKeyAction) -> Void)?

    @ObservationIgnored private var hotKeys: [HotKeyAction: HotKey] = [:]
    private let store: HotKeyBindingStore

    init(store: HotKeyBindingStore = HotKeyBindingStore(defaults: .standard)) {
        self.store = store
        store.migrateLegacyIfNeeded()
    }

    func registerAll() {
        for action in HotKeyAction.allCases {
            apply(store.binding(for: action), to: action)
        }
    }

    /// `nil` disables the action.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        store.save(binding, for: action)
        apply(binding, to: action)
    }

    func reset(_ action: HotKeyAction) {
        store.reset(action)
        apply(store.binding(for: action), to: action)
    }

    /// True while every hotkey is paused (recording a new one, or later a capture session).
    private(set) var isSuspended = false

    /// Unregisters every hotkey (while recording a new one, or during a capture session).
    func suspendAll() {
        isSuspended = true
        hotKeys.values.forEach { $0.isPaused = true }
    }

    func resumeAll() {
        isSuspended = false
        hotKeys.values.forEach { $0.isPaused = false }
    }

    // MARK: - Private

    private func apply(_ binding: HotKeyBinding?, to action: HotKeyAction) {
        hotKeys[action] = nil // deinit unregisters the old Carbon hotkey
        bindings[action] = binding
        guard let binding else { return }

        let hotKey = HotKey(keyCombo: binding.keyCombo)
        hotKey.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onAction?(action)
            }
        }
        hotKeys[action] = hotKey
    }
}
