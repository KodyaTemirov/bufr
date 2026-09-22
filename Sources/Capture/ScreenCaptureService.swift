import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// Thin ScreenCaptureKit wrapper. Bufr's own windows are never in a capture.
@MainActor
final class ScreenCaptureService {
    enum CaptureError: Error {
        case displayNotFound
        case windowNotFound
        case noImage
    }

    struct Capture {
        let image: CGImage
        let pointScale: CGFloat
    }

    /// Also the call that triggers macOS's own Screen Recording consent prompt, so it runs
    /// before any overlay could hide that prompt.
    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func captureDisplay(_ displayID: CGDirectDisplayID, content: SCShareableContent, showsCursor: Bool) async throws -> Capture {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = showsCursor
        return try await capture(filter: filter, configuration: configuration)
    }

    func captureWindow(_ windowID: CGWindowID, content: SCShareableContent, shadow: Bool) async throws -> Capture {
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = !shadow
        configuration.includeChildWindows = true
        return try await capture(filter: filter, configuration: configuration)
    }

    private func capture(filter: SCContentFilter, configuration: SCScreenshotConfiguration) async throws -> Capture {
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        let scale = filter.pointPixelScale > 0 ? CGFloat(filter.pointPixelScale) : 1
        return Capture(image: image, pointScale: scale)
    }

    /// Cuts a display-local rect (points, top-left origin) out of a full-display image.
    nonisolated static func crop(_ image: CGImage, localRect: CGRect, displayPointSize: CGSize) -> CGImage? {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: localRect,
            displayPointSize: displayPointSize,
            imagePixelSize: CGSize(width: image.width, height: image.height)
        )
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return nil }
        return image.cropping(to: pixels)
    }
}
