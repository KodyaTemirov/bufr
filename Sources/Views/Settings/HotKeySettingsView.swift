import SwiftUI
import HotKey

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n("hotkeys.openPanel"))

                    Spacer()

                    if isRecording {
                        Text(L10n("hotkeys.prompt"))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    } else {
                        Text(appState.hotKeyDisplayString)
                            .font(.system(.title3, design: .monospaced, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quinary, in: .rect(cornerRadius: 8))
                    }
                }

                HStack {
                    Button(isRecording ? L10n("common.cancel") : L10n("hotkeys.record")) {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }

                    if !isRecording {
                        Button(L10n("hotkeys.reset")) {
                            appState.resetHotKey()
                        }
                    }
                }
            } header: {
                Label(L10n("hotkeys.header"), systemImage: "command")
            }

            Section {
                Text(L10n("hotkeys.tip.text"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(L10n("hotkeys.tip.header"), systemImage: "lightbulb")
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        appState.hotKeyManager.unregister()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]) != [] else {
                return event
            }

            if let key = Key(carbonKeyCode: UInt32(event.keyCode)) {
                let mods = event.modifierFlags
                appState.hotKeyManager.register(key: key, modifiers: mods)
                appState.hotKeyDisplayString = displayString(key: key, modifiers: mods)
                appState.saveHotKey(key: key, modifiers: mods)
            }

            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if appState.hotKeyManager.isRegistered == false {
            appState.resetHotKey()
        }
    }

    private func displayString(key: Key, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(key.description.uppercased())
        return parts.joined()
    }
}
