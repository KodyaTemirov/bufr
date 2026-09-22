import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(L10n(action.titleKey))

                        Spacer()

                        HotKeyRecorderView(action: action)

                        Button(L10n("hotkeys.reset")) {
                            appState.hotKeyManager.reset(action)
                        }
                        .disabled(appState.hotKeyManager.bindings[action] == action.defaultBinding)
                    }
                }
            } header: {
                Label(L10n("hotkeys.header"), systemImage: "command")
            } footer: {
                Text(L10n("hotkeys.recorder.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
