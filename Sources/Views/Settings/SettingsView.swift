import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case exclusions
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n("settings.tab.general")
        case .hotkeys: L10n("settings.tab.hotkeys")
        case .exclusions: L10n("settings.tab.exclusions")
        case .updates: L10n("settings.tab.updates")
        case .about: L10n("settings.tab.about")
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .hotkeys: "keyboard"
        case .exclusions: "eye.slash"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            // Detail
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .hotkeys:
                    HotKeySettingsView()
                case .exclusions:
                    ExclusionsSettingsView()
                case .updates:
                    UpdateSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .environment(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 600)
        .id(appState.appLanguage)
    }
}
