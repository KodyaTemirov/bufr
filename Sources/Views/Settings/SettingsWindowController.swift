import AppKit
import SwiftUI

/// Owns the Settings window. Replaces the SwiftUI `Settings` scene so any code
/// (panel, menu bar, permission guides) can open Settings on a specific tab.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let selection = SettingsSelection()
    private var window: NSWindow?

    private init() {}

    func show(tab: SettingsTab? = nil) {
        if let tab {
            selection.tab = tab
        }
        let window = self.window ?? makeWindow()
        self.window = window
        window.title = L10n("settings.window.title") // language may have changed since creation
        AppActivation.present(window)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(selection: selection)
            .environment(AppState.shared)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 680, height: 600)) // SettingsView's fixed frame
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
