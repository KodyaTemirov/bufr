import AppKit
import SwiftUI

enum PanelPosition: String, CaseIterable {
    case bottom
    case top
}

@MainActor
final class PanelManager {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<AnyView>?

    var onPanelClose: (() -> Void)?

    func showPanel(content: some View, position: PanelPosition = .bottom) {
        guard let screen = NSScreen.main else { return }

        let panelHeight: CGFloat = 280

        // Start off-screen for animation
        let offScreenY: CGFloat
        let targetY: CGFloat
        let originX: CGFloat
        let panelWidth: CGFloat

        switch position {
        case .bottom:
            let horizontalInset: CGFloat = 8
            originX = screen.visibleFrame.origin.x + horizontalInset
            panelWidth = screen.visibleFrame.width - horizontalInset * 2
            offScreenY = screen.frame.origin.y - panelHeight
            targetY = screen.frame.origin.y
        case .top:
            let horizontalInset: CGFloat = 8
            originX = screen.visibleFrame.origin.x + horizontalInset
            panelWidth = screen.visibleFrame.width - horizontalInset * 2
            offScreenY = screen.visibleFrame.origin.y + screen.visibleFrame.height + panelHeight
            targetY = screen.visibleFrame.origin.y + screen.visibleFrame.height - panelHeight - horizontalInset
        }

        let startRect = NSRect(x: originX, y: offScreenY, width: panelWidth, height: panelHeight)
        let targetRect = NSRect(x: originX, y: targetY, width: panelWidth, height: panelHeight)

        let wrappedContent = AnyView(content)

        if let panel {
            // Reuse existing panel — update content and reset position
            if let hostingView {
                hostingView.rootView = wrappedContent
            }
            panel.setFrame(startRect, display: false)
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            // Create panel once
            let newPanel = FloatingPanel(contentRect: startRect)
            newPanel.onClickOutside = { [weak self] in
                self?.hidePanel()
            }
            let hosting = NSHostingView(rootView: wrappedContent)
            hosting.frame = NSRect(origin: .zero, size: startRect.size)
            hosting.autoresizingMask = [.width, .height]
            newPanel.contentView = hosting
            newPanel.applyCornerMask()
            self.hostingView = hosting
            self.panel = newPanel
            newPanel.orderFrontRegardless()
            newPanel.makeKey()
        }

        // Animate slide in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(targetRect, display: true)
            self.panel?.animator().alphaValue = 1.0
        }
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        guard let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }

        let panelHeight = panel.frame.height
        let offScreenY = screen.frame.origin.y - panelHeight

        let targetRect = NSRect(
            x: panel.frame.origin.x,
            y: offScreenY,
            width: panel.frame.width,
            height: panelHeight
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1.0
                self?.onPanelClose?()
            }
        })
    }

    func togglePanel(content: some View, position: PanelPosition = .bottom) {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel(content: content, position: position)
        }
    }

    func adjustHeight(by delta: CGFloat) {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        frame.size.height += delta
        frame.origin.y -= delta
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
