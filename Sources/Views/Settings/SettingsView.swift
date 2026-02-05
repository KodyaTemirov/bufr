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
        }
        .frame(width: 480, height: 380)
    }
}
