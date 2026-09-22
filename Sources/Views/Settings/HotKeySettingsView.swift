import SwiftUI

struct HotKeySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            if !appState.hotKeyManager.blockedBySystem.isEmpty {
                Section {
                    SystemShortcutsBanner()
                }
            }

            ForEach(HotKeyAction.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(HotKeyAction.allCases.filter { $0.group == group }, id: \.self) { action in
                        row(for: action)
                    }
                } header: {
                    Label(L10n(group.titleKey), systemImage: group.systemImage)
                } footer: {
                    if group == HotKeyAction.Group.allCases.last {
                        Text(L10n("hotkeys.recorder.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

    private func row(for action: HotKeyAction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n(action.titleKey))
                if appState.hotKeyManager.blockedBySystem.contains(action) {
                    Text(L10n("hotkeys.blockedBySystem"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            HotKeyRecorderView(action: action)

            Button(L10n("hotkeys.reset")) {
                appState.hotKeyManager.reset(action)
            }
            .disabled(appState.hotKeyManager.bindings[action] == action.defaultBinding)
        }
    }
}

private extension HotKeyAction.Group {
    var titleKey: String {
        switch self {
        case .panel: "hotkeys.group.panel"
        case .screenshots: "hotkeys.group.screenshots"
        }
    }

    var systemImage: String {
        switch self {
        case .panel: "clipboard"
        case .screenshots: "camera.viewfinder"
        }
    }
}
