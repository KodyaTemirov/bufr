import AppKit
import Carbon.HIToolbox
import HotKey

/// One shortcut-recording session: a local key monitor plus suspended global hotkeys.
/// Ends on Esc, ⌫, a valid combo, or when the hosting window closes or loses key status —
/// the Settings window is reused, so SwiftUI's onDisappear does not fire when it closes.
@MainActor @Observable
final class HotKeyRecording {
    private(set) var isActive = false
    private(set) var liveModifiers: NSEvent.ModifierFlags = []

    @ObservationIgnored private let action: HotKeyAction
    @ObservationIgnored private let manager: HotKeyManager
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []

    init(action: HotKeyAction, manager: HotKeyManager) {
        self.action = action
        self.manager = manager
    }

    func start(in window: NSWindow?) {
        guard !isActive else { return }
        isActive = true
        // A registered Carbon hotkey would swallow the key press before we see it
        manager.suspendAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event) ?? event
        }

        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            // queue: nil delivers synchronously on the posting (main) thread
            let observer = NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
            windowObservers.append(observer)
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        liveModifiers = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
        manager.resumeAll()
    }

    /// Internal (not private) so tests can feed synthetic events.
    func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(HotKeyBinding.relevantModifiers)

        if event.type == .flagsChanged {
            liveModifiers = modifiers
            return event
        }

        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty && keyCode == kVK_Escape {
            stop()
            return nil
        }
        if modifiers.isEmpty && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            manager.setBinding(nil, for: action)
            stop()
            return nil
        }

        // At least one of ⌘ ⌥ ⌃ is required so plain typing is never hijacked
        guard !modifiers.intersection([.command, .option, .control]).isEmpty,
              let key = Key(carbonKeyCode: UInt32(event.keyCode))
        else {
            NSSound.beep()
            return nil
        }

        let binding = HotKeyBinding(key: key, modifiers: modifiers)
        // Another action already uses it: keep recording so the user can pick another combo
        if manager.action(using: binding, excluding: action) != nil {
            NSSound.beep()
            return nil
        }

        manager.setBinding(binding, for: action)
        stop()
        return nil
    }
}
