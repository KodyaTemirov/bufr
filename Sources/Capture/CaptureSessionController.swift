import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

private let logger = Logger(subsystem: "com.bufr.app", category: "CaptureSession")

/// Runs one capture: freezes every display, lets the user pick on overlays, and returns the image.
/// Only one session runs at a time.
@MainActor
final class CaptureSessionController {
    struct Options {
        var showsCursor: Bool
        var windowShadow: Bool
        var showMagnifier: Bool
        var previousArea: CaptureRegion?
    }

    private(set) var isActive = false

    private let service = ScreenCaptureService()
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var overlayViews: [CaptureOverlayView] = []
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?
    private var observers: [NSObjectProtocol] = []
    private var previousArea: CaptureRegion?

    /// Returns nil when the user cancels.
    func capture(_ mode: CaptureMode, options: Options) async throws -> CaptureOutcome? {
        guard !isActive else { return nil }
        isActive = true
        defer { isActive = false }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let content = try await service.shareableContent()

        switch mode {
        case .fullscreen:
            guard let displayID = DisplayInfo.screenUnderMouse()?.displayID else {
                throw ScreenCaptureService.CaptureError.displayNotFound
            }
            let capture = try await service.captureDisplay(displayID, content: content, showsCursor: options.showsCursor)
            return CaptureOutcome(
                image: capture.image, pointScale: capture.pointScale,
                sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                region: nil
            )

        case .previousArea:
            if let region = options.previousArea,
               let displayID = DisplayInfo.displayID(forUUID: region.displayUUID),
               let screen = DisplayInfo.screen(for: displayID) {
                let capture = try await service.captureDisplay(displayID, content: content, showsCursor: false)
                guard let image = ScreenCaptureService.crop(capture.image, localRect: region.localRect, displayPointSize: screen.frame.size)
                else { return nil }
                return CaptureOutcome(
                    image: image, pointScale: capture.pointScale,
                    sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                    region: region
                )
            }
            // No previous area yet, or its display is gone: let the user pick one
            return try await interactiveCapture(windowMode: false, content: content, options: options, frontmost: frontmost)

        case .area, .window:
            return try await interactiveCapture(windowMode: mode == .window, content: content, options: options, frontmost: frontmost)
        }
    }

    /// Ends the running selection without a result (Esc, a second hotkey press, app switch).
    func cancel() {
        finish(nil)
    }

    // MARK: - Interactive

    private func interactiveCapture(
        windowMode: Bool,
        content: SCShareableContent,
        options: Options,
        frontmost: NSRunningApplication?
    ) async throws -> CaptureOutcome? {
        // Freeze every display before any overlay exists: the overlay shows exactly this image
        var frames: [CGDirectDisplayID: ScreenCaptureService.Capture] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            frames[displayID] = try await service.captureDisplay(displayID, content: content, showsCursor: false)
        }
        let windows = WindowListProvider.snapshot()
        previousArea = options.previousArea

        guard let selection = await present(frames: frames, windows: windows, windowMode: windowMode, showMagnifier: options.showMagnifier)
        else { return nil }

        switch selection {
        case let .area(displayID, localRect):
            guard let frame = frames[displayID],
                  let screen = DisplayInfo.screen(for: displayID),
                  let image = ScreenCaptureService.crop(frame.image, localRect: localRect, displayPointSize: screen.frame.size)
            else { return nil }
            let region = DisplayInfo.uuidString(for: displayID).map { CaptureRegion(displayUUID: $0, localRect: localRect) }
            return CaptureOutcome(
                image: image, pointScale: frame.pointScale,
                sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                region: region
            )

        case let .window(window):
            let capture = try await service.captureWindow(window.windowID, content: content, shadow: options.windowShadow)
            let owner = NSRunningApplication(processIdentifier: window.ownerPID)
            return CaptureOutcome(
                image: capture.image, pointScale: capture.pointScale,
                sourceAppId: owner?.bundleIdentifier, sourceAppName: owner?.localizedName ?? window.ownerName,
                region: nil
            )
        }
    }

    private func present(
        frames: [CGDirectDisplayID: ScreenCaptureService.Capture],
        windows: [CapturableWindow],
        windowMode: Bool,
        showMagnifier: Bool
    ) async -> CaptureSelection? {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let primaryHeight = DisplayInfo.primaryHeight

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, let frame = frames[displayID] else { continue }
            let view = CaptureOverlayView(
                configuration: .init(
                    image: frame.image,
                    displayID: displayID,
                    screenFrame: screen.frame,
                    primaryHeight: primaryHeight,
                    backingScale: screen.backingScaleFactor,
                    windows: windows,
                    showMagnifier: showMagnifier
                ),
                windowMode: windowMode
            )
            view.delegate = self
            overlayViews.append(view)
            overlayWindows.append(CaptureOverlayWindow(screen: screen, view: view))
        }

        // Activating Bufr makes key events, the crosshair cursor and first responder reliable
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        if let keyWindow = overlayWindows.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? overlayWindows.first {
            keyWindow.makeKey()
            keyWindow.makeFirstResponder(keyWindow.contentView)
        }
        observeCancellation()

        let selection = await withCheckedContinuation { continuation = $0 }

        tearDown()
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
        return selection
    }

    private func observeCancellation() {
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancel()
                }
            })
        }
    }

    private func finish(_ selection: CaptureSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selection)
    }

    private func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows = []
        overlayViews = [] // releases the frozen frames (tens of MB each on 5K displays)
    }
}

// MARK: - CaptureOverlayViewDelegate

extension CaptureSessionController: CaptureOverlayViewDelegate {
    func overlayView(_ view: CaptureOverlayView, didSelect selection: CaptureSelection) {
        finish(selection)
    }

    func overlayViewDidCancel(_ view: CaptureOverlayView) {
        finish(nil)
    }

    func overlayView(_ view: CaptureOverlayView, didSwitchToWindowMode windowMode: Bool) {
        overlayViews.forEach { $0.windowMode = windowMode }
    }

    func overlayViewDidRequestPreviousArea(_ view: CaptureOverlayView) {
        guard let region = previousArea,
              let displayID = DisplayInfo.displayID(forUUID: region.displayUUID)
        else {
            NSSound.beep()
            return
        }
        finish(.area(displayID: displayID, localRect: region.localRect))
    }

    func overlayViewMouseEntered(_ view: CaptureOverlayView) {
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }
}
