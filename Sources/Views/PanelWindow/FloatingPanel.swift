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

        level = .init(NSWindow.Level.mainMenu.rawValue + 1)
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

    // Forward vertical scroll wheel events to the horizontal NSScrollView
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel,
           abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
           let scrollView = findHorizontalScrollView(in: contentView) {
            scrollView.scrollWheel(with: event)
            return
        }
        super.sendEvent(event)
    }

    private func findHorizontalScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        for subview in view.subviews {
            if let sv = subview as? NSScrollView, sv.hasHorizontalScroller {
                return sv
            }
            if let found = findHorizontalScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        // Delay monitoring to avoid catching the click that opened the panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isVisible else { return }
            self.startMonitoringClicks()
        }
    }

    override func orderOut(_ sender: Any?) {
        stopMonitoringClicks()
        super.orderOut(sender)
    }

    func suspendClickMonitoring() {
        stopMonitoringClicks()
    }

    func resumeClickMonitoring() {
        guard isVisible else { return }
        startMonitoringClicks()
    }

    private func startMonitoringClicks() {
        stopMonitoringClicks()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }

            let screenPoint = NSEvent.mouseLocation

            // Don't close if click lands on any app window (panels, sheets, menus)
            for window in NSApp.windows where window.isVisible {
                if window.frame.contains(screenPoint) {
                    return
                }
            }

            // Also don't close if a modal panel is running
            if NSApp.modalWindow != nil {
                return
            }

            Task { @MainActor in
                self.onClickOutside?()
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
