import AppKit

/// Non-activating floating panel that doesn't steal focus from the active app
final class FloatingPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    nonisolated(unsafe) private var clickOutsideMonitor: Any?
    nonisolated(unsafe) private var scrollMonitor: Any?
    nonisolated(unsafe) private var keyMonitor: Any?
    var remapScrollToHorizontal: Bool = true
    static let arrowKeyNotification = Notification.Name("FloatingPanel.arrowKey")

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
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
    }

    /// Clips the contentView layer to rounded corners so glass doesn't leak.
    func applyCornerMask(radius: CGFloat = 0) {
        guard let contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = radius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = radius > 0
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
        startScrollMonitor()
        startKeyMonitor()
        // Delay monitoring to avoid catching the click that opened the panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isVisible else { return }
            self.startMonitoringClicks()
        }
    }

    override func orderOut(_ sender: Any?) {
        stopMonitoringClicks()
        stopScrollMonitor()
        stopKeyMonitor()
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

    // MARK: - Scroll: vertical → horizontal

    private func startScrollMonitor() {
        stopScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.remapScrollToHorizontal, self.isVisible,
                  let contentView = self.contentView,
                  contentView.frame.contains(event.locationInWindow),
                  event.window === self
            else { return event }

            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let cgEvent = event.cgEvent?.copy()
            else { return event }

            let dy1 = cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let dy2 = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dy3 = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)

            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: dy1)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dy2)
            cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dy3)

            return NSEvent(cgEvent: cgEvent) ?? event
        }
    }

    private func stopScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Arrow keys: bypass TextField focus

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self else { return event }

            let arrows: [UInt16: Int] = [123: -1, 124: 1, 125: 1, 126: -1] // left, right, down, up
            if let direction = arrows[event.keyCode] {
                NotificationCenter.default.post(
                    name: FloatingPanel.arrowKeyNotification,
                    object: nil,
                    userInfo: ["direction": direction]
                )
                return nil // consume event
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
