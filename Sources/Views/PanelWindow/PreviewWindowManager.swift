import AppKit
import SwiftUI

@MainActor
final class PreviewWindowManager {
    static let shared = PreviewWindowManager()

    private var panel: NSPanel?
    private var onDismiss: (() -> Void)?

    func show(item: ClipItem, appState: AppState, onDismiss: @escaping () -> Void) {
        close()
        self.onDismiss = onDismiss

        guard let screen = NSScreen.main else { return }

        let width = screen.frame.width * 0.65
        let height = screen.frame.height * 0.7
        let x = screen.frame.midX - width / 2
        let y = screen.frame.midY - height / 2
        let rect = NSRect(x: x, y: y, width: width, height: height)

        let newPanel = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .init(NSWindow.Level.mainMenu.rawValue + 2)
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true

        let content = QuickPreviewView(item: item) { [weak self] in
            self?.close()
        }
        .environment(appState)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: rect.size)
        hosting.autoresizingMask = [.width, .height]
        newPanel.contentView = hosting

        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()
        newPanel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            newPanel.animator().alphaValue = 1
        }

        self.panel = newPanel
    }

    func close() {
        guard let panel else { return }
        let dismiss = onDismiss
        onDismiss = nil

        panel.alphaValue = 0
        panel.orderOut(nil)
        self.panel = nil
        dismiss?()
    }
}
