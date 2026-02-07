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

    // Convert vertical scroll to horizontal so the card strip scrolls with
    // mouse wheel / trackpad vertical swipe.
    override func scrollWheel(with event: NSEvent) {
        // Only remap when vertical component dominates
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }

        // Build a copy with axes swapped
        if let cg = event.cgEvent?.copy() {
            let dy1 = cg.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let dy2 = cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dy3 = cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

            cg.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: -dy1)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -dy2)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -dy3)

            if let remapped = NSEvent(cgEvent: cg) {
                super.scrollWheel(with: remapped)
                return
            }
        }

        super.scrollWheel(with: event)
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
