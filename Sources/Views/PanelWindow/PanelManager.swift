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
    private var currentPosition: PanelPosition = .bottom
    private var isAnimating = false

    var onPanelClose: (() -> Void)?

    /// Returns the screen where the mouse cursor is currently located.
    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    func showPanel(content: some View, position: PanelPosition = .bottom) {
        guard !isAnimating, let screen = activeScreen() else { return }

        currentPosition = position
        let panelHeight: CGFloat = 280
        let horizontalInset: CGFloat = 8

        let originX = screen.visibleFrame.origin.x + horizontalInset
        let panelWidth = screen.visibleFrame.width - horizontalInset * 2

        // Short slide (30pt) + fade so animation stays within the current screen
        let slideOffset: CGFloat = 30
        let targetY: CGFloat

        switch position {
        case .bottom:
            targetY = screen.frame.origin.y
        case .top:
            targetY = screen.visibleFrame.origin.y + screen.visibleFrame.height - panelHeight - horizontalInset
        }

        let startY = position == .bottom ? targetY - slideOffset : targetY + slideOffset
        let startRect = NSRect(x: originX, y: startY, width: panelWidth, height: panelHeight)
        let targetRect = NSRect(x: originX, y: targetY, width: panelWidth, height: panelHeight)

        let wrappedContent = AnyView(content)

        if let panel {
            // Reuse existing panel — update content and reset position
            if let hostingView {
                hostingView.rootView = wrappedContent
            }
            panel.alphaValue = 0.0
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
            newPanel.alphaValue = 0.0
            self.hostingView = hosting
            self.panel = newPanel
            newPanel.orderFrontRegardless()
            newPanel.makeKey()
        }

        // Animate slide in
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(targetRect, display: true)
            self.panel?.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
        })
    }

    func hidePanel() {
        guard !isAnimating, let panel, panel.isVisible else { return }

        // Short slide (30pt) + fade out, stays within the current screen
        let slideOffset: CGFloat = 30
        let hideY = currentPosition == .bottom
            ? panel.frame.origin.y - slideOffset
            : panel.frame.origin.y + slideOffset

        let targetRect = NSRect(
            x: panel.frame.origin.x,
            y: hideY,
            width: panel.frame.width,
            height: panel.frame.height
        )

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1.0
                self?.isAnimating = false
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

    func suspendClickMonitoring() {
        panel?.suspendClickMonitoring()
    }

    func resumeClickMonitoring() {
        panel?.resumeClickMonitoring()
    }
}
