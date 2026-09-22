import AppKit
import HotKey

/// Registers one Carbon hotkey per `HotKeyAction` and reports presses through `onAction`.
@MainActor @Observable
final class HotKeyManager {
    /// Current bindings; an action without an entry is disabled.
    private(set) var bindings: [HotKeyAction: HotKeyBinding] = [:]
    /// Actions whose combo an enabled macOS shortcut already uses; they stay unregistered
    /// until the user turns the system shortcut off.
    private(set) var blockedBySystem: Set<HotKeyAction> = []
    var onAction: ((HotKeyAction) -> Void)?

    @ObservationIgnored private var hotKeys: [HotKeyAction: HotKey] = [:]
    @ObservationIgnored private var conflictTimer: Timer?
    private let store: HotKeyBindingStore
    private let systemShortcuts: () -> Set<HotKeyBinding>

    init(
        store: HotKeyBindingStore = HotKeyBindingStore(defaults: .standard),
        systemShortcuts: @escaping () -> Set<HotKeyBinding> = SystemShortcutInspector.enabledScreenshotShortcuts
    ) {
        self.store = store
        self.systemShortcuts = systemShortcuts
        store.migrateLegacyIfNeeded()
    }

    func registerAll() {
        let system = systemShortcuts()
        for action in HotKeyAction.allCases {
            apply(store.binding(for: action), to: action, system: system)
        }
        updateConflictTimer()
    }

    /// `nil` disables the action.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        store.save(binding, for: action)
        apply(binding, to: action, system: systemShortcuts())
        updateConflictTimer()
    }

    func reset(_ action: HotKeyAction) {
        store.reset(action)
        apply(store.binding(for: action), to: action, system: systemShortcuts())
        updateConflictTimer()
    }

    /// Re-reads macOS shortcuts and registers or blocks actions whose state changed.
    func recheckSystemConflicts() {
        let system = systemShortcuts()
        for action in HotKeyAction.allCases {
            let shouldBlock = bindings[action].map { system.contains($0) } ?? false
            if shouldBlock != blockedBySystem.contains(action) {
                apply(bindings[action], to: action, system: system)
            }
        }
        updateConflictTimer()
    }

    func isRegistered(_ action: HotKeyAction) -> Bool {
        hotKeys[action] != nil
    }

    /// The combo that currently triggers `action` in Bufr: nil when unset or owned by macOS.
    func activeBinding(for action: HotKeyAction) -> HotKeyBinding? {
        blockedBySystem.contains(action) ? nil : bindings[action]
    }

    /// Re-reads macOS shortcuts right before acting on a press. If the user turned the macOS
    /// screenshot shortcut back on, both would fire; Bufr steps aside instead.
    @discardableResult
    func confirmStillOwned(_ action: HotKeyAction) -> Bool {
        recheckSystemConflicts()
        return !blockedBySystem.contains(action)
    }

    /// The other action already bound to `binding`, if any.
    func action(using binding: HotKeyBinding, excluding action: HotKeyAction) -> HotKeyAction? {
        bindings.first { $0.key != action && $0.value == binding }?.key
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

    private func apply(_ binding: HotKeyBinding?, to action: HotKeyAction, system: Set<HotKeyBinding>) {
        hotKeys[action] = nil // deinit unregisters the old Carbon hotkey
        bindings[action] = binding
        blockedBySystem.remove(action)
        guard let binding else { return }

        if system.contains(binding) {
            blockedBySystem.insert(action)
            return
        }

        let hotKey = HotKey(keyCombo: binding.keyCombo)
        hotKey.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onAction?(action)
            }
        }
        if isSuspended {
            hotKey.isPaused = true // bound while recording: activates on resumeAll()
        }
        hotKeys[action] = hotKey
    }

    /// While something is blocked, re-check every 10 s so disabling the macOS shortcut
    /// takes effect without restarting Bufr.
    private func updateConflictTimer() {
        if blockedBySystem.isEmpty {
            conflictTimer?.invalidate()
            conflictTimer = nil
        } else if conflictTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recheckSystemConflicts()
                }
            }
            timer.tolerance = 3
            conflictTimer = timer
        }
    }
}
