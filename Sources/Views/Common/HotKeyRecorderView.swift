import AppKit
import Carbon.HIToolbox
import HotKey
import SwiftUI

/// Click to record a new shortcut. Esc cancels, ⌫ disables the action.
/// At least one of ⌘ ⌥ ⌃ is required so plain typing is never hijacked.
struct HotKeyRecorderView: View {
    let action: HotKeyAction

    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.1)) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording {
            return liveModifiers.isEmpty ? L10n("hotkeys.prompt") : HotKeyBinding.modifierSymbols(liveModifiers)
        }
        return appState.hotKeyManager.bindings[action]?.displayString ?? L10n("hotkeys.none")
    }

    private func startRecording() {
        isRecording = true
        // A registered Carbon hotkey would swallow the key press before we see it
        appState.hotKeyManager.suspendAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(HotKeyBinding.relevantModifiers)

        if event.type == .flagsChanged {
            liveModifiers = modifiers
            return event
        }

        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty && keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        if modifiers.isEmpty && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            appState.hotKeyManager.setBinding(nil, for: action)
            stopRecording()
            return nil
        }

        guard !modifiers.intersection([.command, .option, .control]).isEmpty,
              let key = Key(carbonKeyCode: UInt32(event.keyCode))
        else {
            NSSound.beep()
            return nil
        }

        appState.hotKeyManager.setBinding(HotKeyBinding(key: key, modifiers: modifiers), for: action)
        stopRecording()
        return nil
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        appState.hotKeyManager.resumeAll()
    }
}
