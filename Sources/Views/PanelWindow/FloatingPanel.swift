import AppKit

/// Non-activating floating panel that doesn't steal focus from the active app
final class FloatingPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    nonisolated(unsafe) private var clickOutsideMonitor: Any?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
    }

    /// Clips the contentView layer to rounded corners so glass doesn't leak.
    func applyCornerMask(radius: CGFloat = 18) {
        guard let contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = radius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
    }

    // Allow the panel to become key to receive keyboard events
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Close on Escape
    override func cancelOperation(_ sender: Any?) {
        onClickOutside?()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        startMonitoringClicks()
    }

    override func orderOut(_ sender: Any?) {
        stopMonitoringClicks()
        super.orderOut(sender)
    }

    private func startMonitoringClicks() {
        stopMonitoringClicks()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            let screenPoint = NSEvent.mouseLocation
            if !self.frame.contains(screenPoint) {
                Task { @MainActor in
                    self.onClickOutside?()
                }
            }
        }
    }

    private func stopMonitoringClicks() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
