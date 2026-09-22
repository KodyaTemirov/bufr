import AppKit
import SwiftUI

/// Shows one SwiftUI view in a regular window, at most once at a time. Closing drops the
/// window and its view, so tasks inside the view (status polling) stop.
@MainActor
final class SingleWindowPresenter {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show(title: String, @ViewBuilder content: (_ close: @escaping () -> Void) -> some View) {
        if let window {
            window.title = title
            AppActivation.present(window)
            return
        }

        let root = content { [weak self] in self?.window?.close() }
            .environment(AppState.shared)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable]
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWillClose()
            }
        }
        self.window = window
        AppActivation.present(window)
    }

    private func windowWillClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window = nil
    }
}
