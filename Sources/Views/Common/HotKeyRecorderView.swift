import AppKit
import SwiftUI

/// Click to record a new shortcut. Esc cancels, ⌫ disables the action.
struct HotKeyRecorderView: View {
    let action: HotKeyAction

    @Environment(AppState.self) private var appState
    @State private var recording: HotKeyRecording?

    private var isRecording: Bool { recording?.isActive == true }

    var body: some View {
        Button {
            if isRecording { recording?.stop() } else { startRecording() }
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
        .onDisappear { recording?.stop() }
    }

    private var label: String {
        if let recording, recording.isActive {
            return recording.liveModifiers.isEmpty
                ? L10n("hotkeys.prompt")
                : HotKeyBinding.modifierSymbols(recording.liveModifiers)
        }
        return appState.hotKeyManager.bindings[action]?.displayString ?? L10n("hotkeys.none")
    }

    private func startRecording() {
        let recording = HotKeyRecording(action: action, manager: appState.hotKeyManager)
        // The Settings window is key while its button is being clicked
        recording.start(in: NSApp.keyWindow)
        self.recording = recording
    }
}
