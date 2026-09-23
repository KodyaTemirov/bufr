import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Live frames of the region being scrolled.
@MainActor
protocol ScrollFrameSource: AnyObject {
    /// `onFrame` gets each new frame; `onFailure` when the stream stops by itself
    /// (display disconnected, permission revoked).
    func start(onFrame: @escaping @MainActor (CGImage) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws
    func stop() async
}

/// ScreenCaptureKit stream of the region, without Bufr's own windows (its frame and controls
/// sit on top of the region). ScreenCaptureKit only sends a frame when the picture changed.
@MainActor
final class StreamFrameSource: ScrollFrameSource {
    private let region: ScrollRegion
    private var stream: SCStream?
    private let output = StreamOutput()

    init(region: ScrollRegion) {
        self.region = region
    }

    func start(onFrame: @escaping @MainActor (CGImage) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureService.CaptureError.displayNotFound
        }
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.localRect
        configuration.width = Int(region.pixelSize.width)
        configuration.height = Int(region.pixelSize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 12)
        configuration.showsCursor = false
        configuration.queueDepth = 3

        output.onFrame = { image in
            Task { @MainActor in onFrame(image) }
        }
        output.onFailure = { error in
            Task { @MainActor in onFailure(error) }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }
}

/// Receives frames on its own queue. The callbacks are set before the stream starts and never
/// change afterwards.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.bufr.scrolling-capture.frames", qos: .userInteractive)
    var onFrame: @Sendable (CGImage) -> Void = { _ in }
    var onFailure: @Sendable (Error) -> Void = { _ in }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let image = FrameConversion.image(from: pixelBuffer)
        else { return }
        onFrame(image)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error)
    }
}

enum FrameConversion {
    /// A copy of a BGRA pixel buffer's pixels: the stream reuses its buffers for later frames.
    static func image(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowBytes = width * 4
        var bytes = Data(count: rowBytes * height)
        bytes.withUnsafeMutableBytes { destination in
            guard let target = destination.baseAddress else { return }
            for row in 0..<height {
                memcpy(target + row * rowBytes, base + row * sourceRowBytes, rowBytes)
            }
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
