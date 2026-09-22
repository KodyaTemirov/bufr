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
        /// Bufr windows that belong in the capture (pinned screenshots)
        var keptWindowIDs: [CGWindowID] = []
    }

    private(set) var isActive = false

    private let service = ScreenCaptureService()
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var overlayViews: [CaptureOverlayView] = []
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var previousArea: CaptureRegion?
    private var toolbarPanel: AllInOneToolbarPanel?
    private var isAdjustableSession = false
    private let toolbarModel = AllInOneToolbarModel()

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
            let capture = try await service.captureDisplay(displayID, content: content, showsCursor: options.showsCursor, keptWindowIDs: options.keptWindowIDs)
            return CaptureOutcome(
                image: capture.image, pointScale: capture.pointScale,
                sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                region: nil, screenRect: DisplayInfo.screen(for: displayID)?.frame
            )

        case .previousArea:
            if let region = options.previousArea,
               let displayID = DisplayInfo.displayID(forUUID: region.displayUUID),
               let screen = DisplayInfo.screen(for: displayID) {
                let capture = try await service.captureDisplay(displayID, content: content, showsCursor: false, keptWindowIDs: options.keptWindowIDs)
                guard let image = ScreenCaptureService.crop(capture.image, localRect: region.localRect, displayPointSize: screen.frame.size)
                else { return nil }
                return CaptureOutcome(
                    image: image, pointScale: capture.pointScale,
                    sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                    region: region,
                    screenRect: ScreenGeometry.cocoaRect(fromLocal: region.localRect, screenFrame: screen.frame)
                )
            }
            // No previous area yet, or its display is gone: let the user pick one
            return try await interactiveCapture(windowMode: false, adjustable: false, content: content, options: options, frontmost: frontmost)

        case .area, .window, .text:
            return try await interactiveCapture(windowMode: mode == .window, adjustable: false, content: content, options: options, frontmost: frontmost)

        case .allInOne:
            return try await interactiveCapture(windowMode: false, adjustable: true, content: content, options: options, frontmost: frontmost)
        }
    }

    /// Ends the running selection without a result (Esc, a second hotkey press, app switch).
    func cancel() {
        finish(nil)
    }

    // MARK: - Interactive

    private func interactiveCapture(
        windowMode: Bool,
        adjustable: Bool,
        content: SCShareableContent,
        options: Options,
        frontmost: NSRunningApplication?
    ) async throws -> CaptureOutcome? {
        // Freeze every display before any overlay exists: the overlay shows exactly this image.
        // A display ScreenCaptureKit can't read (some virtual/DisplayLink ones) is skipped, not fatal.
        var frames: [CGDirectDisplayID: ScreenCaptureService.Capture] = [:]
        var lastError: Error?
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            do {
                frames[displayID] = try await service.captureDisplay(displayID, content: content, showsCursor: false, keptWindowIDs: options.keptWindowIDs)
            } catch {
                logger.error("Display \(displayID) not captured: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        if frames.isEmpty {
            throw lastError ?? ScreenCaptureService.CaptureError.displayNotFound
        }
        let windows = WindowListProvider.snapshot()
        previousArea = options.previousArea

        guard let selection = await present(
            frames: frames, windows: windows, windowMode: windowMode,
            adjustable: adjustable, showMagnifier: options.showMagnifier
        ) else { return nil }

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
                region: region,
                screenRect: ScreenGeometry.cocoaRect(fromLocal: localRect, screenFrame: screen.frame)
            )

        case let .display(displayID):
            guard let frame = frames[displayID] else { return nil }
            return CaptureOutcome(
                image: frame.image, pointScale: frame.pointScale,
                sourceAppId: frontmost?.bundleIdentifier, sourceAppName: frontmost?.localizedName,
                region: nil, screenRect: DisplayInfo.screen(for: displayID)?.frame
            )

        case let .window(window):
            let capture = try await service.captureWindow(window.windowID, content: content, shadow: options.windowShadow)
            let owner = NSRunningApplication(processIdentifier: window.ownerPID)
            return CaptureOutcome(
                image: capture.image, pointScale: capture.pointScale,
                sourceAppId: owner?.bundleIdentifier, sourceAppName: owner?.localizedName ?? window.ownerName,
                region: nil,
                screenRect: ScreenGeometry.cocoaRect(fromCG: window.frame, primaryHeight: DisplayInfo.primaryHeight)
            )
        }
    }

    private func present(
        frames: [CGDirectDisplayID: ScreenCaptureService.Capture],
        windows: [CapturableWindow],
        windowMode: Bool,
        adjustable: Bool,
        showMagnifier: Bool
    ) async -> CaptureSelection? {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let primaryHeight = DisplayInfo.primaryHeight

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, let frame = frames[displayID] else { continue }
            // All-in-one starts from the previous area when it was on this display
            var initialSelection: CGRect?
            if adjustable, let region = previousArea, region.displayUUID == DisplayInfo.uuidString(for: displayID) {
                initialSelection = ScreenGeometry.flipped(region.localRect, height: screen.frame.height)
            }
            let view = CaptureOverlayView(
                configuration: .init(
                    image: frame.image,
                    displayID: displayID,
                    screenFrame: screen.frame,
                    primaryHeight: primaryHeight,
                    backingScale: screen.backingScaleFactor,
                    windows: windows,
                    showMagnifier: showMagnifier,
                    initialSelection: initialSelection
                ),
                windowMode: windowMode,
                adjustable: adjustable
            )
            view.delegate = self
            overlayViews.append(view)
            overlayWindows.append(CaptureOverlayWindow(screen: screen, view: view))
        }

        // Activating Bufr makes key events, the crosshair cursor and first responder reliable
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.orderFrontRegardless() }
        // Keyboard goes to the display holding the preselection (all-in-one), else under the mouse
        isAdjustableSession = adjustable
        let mouse = NSEvent.mouseLocation
        let keyWindow = overlayWindows.first { ($0.contentView as? CaptureOverlayView)?.adjustedLocalSelection != nil }
            ?? overlayWindows.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? overlayWindows.first
        if let keyWindow {
            keyWindow.makeKey()
            keyWindow.makeFirstResponder(keyWindow.contentView)
        }
        if adjustable {
            showToolbar(windowMode: windowMode)
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
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancel()
                }
            }
            observers.append((center, token))
        }

        // macOS may refuse to activate Bufr (cooperative activation); then ⌘Tab never makes it
        // resign active, so watch for any other app becoming active instead
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let token = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isOtherApp = activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                if isOtherApp {
                    self?.cancel()
                }
            }
        }
        observers.append((workspaceCenter, token))
    }

    private func finish(_ selection: CaptureSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selection)
    }

    private func showToolbar(windowMode: Bool) {
        toolbarModel.windowMode = windowMode
        guard let screen = DisplayInfo.screenUnderMouse() else { return }
        let toolbar = AllInOneToolbar(
            model: toolbarModel,
            onArea: { [weak self] in self?.setWindowMode(false) },
            onWindow: { [weak self] in self?.setWindowMode(true) },
            onFullscreen: { [weak self] in self?.captureFullscreenFromToolbar() },
            onCancel: { [weak self] in self?.cancel() },
            onCapture: { [weak self] in self?.captureAdjustedSelection() }
        )
        let panel = AllInOneToolbarPanel(rootView: toolbar, screen: screen)
        panel.orderFrontRegardless()
        toolbarPanel = panel
    }

    private func setWindowMode(_ windowMode: Bool) {
        toolbarModel.windowMode = windowMode
        overlayViews.forEach { $0.windowMode = windowMode }
    }

    private func captureAdjustedSelection() {
        guard let view = overlayViews.first(where: { $0.adjustedLocalSelection != nil }),
              let localRect = view.adjustedLocalSelection
        else {
            NSSound.beep()
            return
        }
        finish(.area(displayID: view.displayID, localRect: localRect))
    }

    /// "Screen" in the mode bar: the whole display under the pointer, from the frozen frame.
    private func captureFullscreenFromToolbar() {
        guard let displayID = DisplayInfo.screenUnderMouse()?.displayID else { return }
        finish(.display(displayID))
    }

    private func tearDown() {
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.close()
        toolbarPanel = nil
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
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
        setWindowMode(windowMode)
    }

    func overlayViewDidAdjust(_ view: CaptureOverlayView) {
        // One editable selection at a time, even across displays; its display gets the keyboard
        for other in overlayViews where other !== view {
            other.clearSelection()
        }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    func overlayViewDidRequestCapture(_ view: CaptureOverlayView) {
        captureAdjustedSelection()
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
        // In all-in-one mode the display holding the selection keeps the keyboard (arrows, Return)
        if isAdjustableSession, overlayViews.contains(where: { $0 !== view && $0.adjustedLocalSelection != nil }) {
            return
        }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }
}
