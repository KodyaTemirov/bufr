import AppKit
import SwiftUI

enum PanelPosition: String, CaseIterable {
    case bottom
    case top
    case left
    case right
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
        let slideOffset: CGFloat = 30

        let targetRect: NSRect
        let startRect: NSRect

        switch position {
        case .bottom:
            let panelHeight: CGFloat = 280
            let panelWidth = screen.visibleFrame.width
            let originX = screen.visibleFrame.origin.x
            let targetY = screen.frame.origin.y
            targetRect = NSRect(x: originX, y: targetY, width: panelWidth, height: panelHeight)
            startRect = targetRect.offsetBy(dx: 0, dy: -slideOffset)

        case .top:
            let panelHeight: CGFloat = 280
            let panelWidth = screen.visibleFrame.width
            let originX = screen.visibleFrame.origin.x
            let targetY = screen.visibleFrame.origin.y + screen.visibleFrame.height - panelHeight
            targetRect = NSRect(x: originX, y: targetY, width: panelWidth, height: panelHeight)
            startRect = targetRect.offsetBy(dx: 0, dy: slideOffset)

        case .left:
            let panelWidth: CGFloat = 280
            let panelHeight = screen.frame.height
            let targetX = screen.frame.origin.x
            let originY = screen.frame.origin.y
            targetRect = NSRect(x: targetX, y: originY, width: panelWidth, height: panelHeight)
            startRect = targetRect.offsetBy(dx: -slideOffset, dy: 0)

        case .right:
            let panelWidth: CGFloat = 280
            let panelHeight = screen.frame.height
            let targetX = screen.frame.origin.x + screen.frame.width - panelWidth
            let originY = screen.frame.origin.y
            targetRect = NSRect(x: targetX, y: originY, width: panelWidth, height: panelHeight)
            startRect = targetRect.offsetBy(dx: slideOffset, dy: 0)
        }

        let wrappedContent = AnyView(content)

        let isHorizontal = position == .bottom || position == .top

        if let panel {
            // Reuse existing panel — update content and reset position
            if let hostingView {
                hostingView.rootView = wrappedContent
            }
            panel.remapScrollToHorizontal = isHorizontal
            panel.alphaValue = 0.0
            panel.setFrame(startRect, display: false)
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            // Create panel once
            let newPanel = FloatingPanel(contentRect: startRect)
            newPanel.remapScrollToHorizontal = isHorizontal
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
        let targetRect: NSRect

        switch currentPosition {
        case .bottom:
            targetRect = panel.frame.offsetBy(dx: 0, dy: -slideOffset)
        case .top:
            targetRect = panel.frame.offsetBy(dx: 0, dy: slideOffset)
        case .left:
            targetRect = panel.frame.offsetBy(dx: -slideOffset, dy: 0)
        case .right:
            targetRect = panel.frame.offsetBy(dx: slideOffset, dy: 0)
        }

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
