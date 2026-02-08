import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false

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
                        isRecording.toggle()
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
    }
}
