import AppKit

/// Bufr runs as an accessory (menu bar) app. While a regular window such as Settings is open,
/// the app switches to `.regular` so the window gets focus, a Dock icon and the standard menus,
/// then switches back when the last such window closes.
@MainActor
enum AppActivation {
    private static var openWindows: Set<ObjectIdentifier> = []
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func present(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if openWindows.insert(id).inserted {
            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    windowWillClose(id)
                }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }

    private static func windowWillClose(_ id: ObjectIdentifier) {
        openWindows.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        if openWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
