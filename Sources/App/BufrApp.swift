import SwiftUI

@main
struct BufrApp: App {
    @State private var appState = AppState()
    @State private var showOnboarding = false

    var body: some Scene {
        MenuBarExtra("Bufr", systemImage: "clipboard") {
            MenuBarView()
                .environment(appState)
                .onAppear {
                    if !appState.hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        appState.hasCompletedOnboarding = true
                    }
                }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
