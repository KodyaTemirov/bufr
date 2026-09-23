import AppKit
import SwiftUI

/// Shows one SwiftUI view in a regular window, at most once at a time. Closing drops the
/// window and its view, so tasks inside the view (status polling) stop.
@MainActor
final class SingleWindowPresenter {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var onClose: () -> Void = {}
    private let present: @MainActor (NSWindow) -> Void

    init(present: @escaping @MainActor (NSWindow) -> Void = { AppActivation.present($0) }) {
        self.present = present
    }

    /// `onClose` runs when the user closes the window (not when the app quits).
    func show(title: String, onClose: @escaping () -> Void = {}, @ViewBuilder content: (_ close: @escaping () -> Void) -> some View) {
        if let window {
            window.title = title
            present(window)
            return
        }

        self.onClose = onClose
        let root = content { [weak self] in self?.close() }
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
        present(window)
    }

    func close() {
        window?.close()
    }

    private func windowWillClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window = nil
        let onClose = onClose
        self.onClose = {}
        onClose()
    }
}
