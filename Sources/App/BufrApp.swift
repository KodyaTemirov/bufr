import SwiftUI

@main
struct BufrApp: App {
    var body: some Scene {
        MenuBarExtra("Bufr", systemImage: "clipboard") {
            MenuBarView()
        }

        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
    }
}
