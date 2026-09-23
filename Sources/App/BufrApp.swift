import SwiftUI

@main
struct BufrApp: App {
    @NSApplicationDelegateAdaptor(BufrAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Bufr", systemImage: "clipboard") {
            MenuBarView()
                .environment(AppState.shared)
        }
    }
}

final class BufrAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.shouldTerminate() ? .terminateNow : .terminateCancel
    }
}
