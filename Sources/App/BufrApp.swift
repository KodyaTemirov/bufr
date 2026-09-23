import SwiftUI

@main
struct BufrApp: App {
    @NSApplicationDelegateAdaptor(BufrAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(AppState.shared)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Bufr")
        }
    }
}

final class BufrAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.shouldTerminate() ? .terminateNow : .terminateCancel
    }
}
