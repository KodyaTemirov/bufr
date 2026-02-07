import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Основные", systemImage: "gear")
                }

            HotKeySettingsView()
                .environment(appState)
                .tabItem {
                    Label("Горячие клавиши", systemImage: "keyboard")
                }

            ExclusionsSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Исключения", systemImage: "eye.slash")
                }

            UpdateSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Обновления", systemImage: "arrow.triangle.2.circlepath")
                }

            AboutSettingsView()
                .environment(appState)
                .tabItem {
                    Label("О приложении", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 520)
    }
}
