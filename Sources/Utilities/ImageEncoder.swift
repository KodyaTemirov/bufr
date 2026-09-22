import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    struct NormalizedImage: Sendable {
        let pngData: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Returns PNG bytes plus pixel size for any ImageIO-readable data.
    /// PNG input is returned byte-for-byte; other formats (TIFF from the pasteboard) are
    /// re-encoded, keeping the DPI so Retina images keep their point size.
    static func normalizedPNG(_ data: Data) -> NormalizedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        if let type = CGImageSourceGetType(source) as String?, type == UTType.png.identifier {
            return NormalizedImage(pngData: data, pixelWidth: width, pixelHeight: height)
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        var outputProperties: [CFString: Any] = [:]
        outputProperties[kCGImagePropertyDPIWidth] = properties[kCGImagePropertyDPIWidth]
        outputProperties[kCGImagePropertyDPIHeight] = properties[kCGImagePropertyDPIHeight]

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return NormalizedImage(pngData: output as Data, pixelWidth: width, pixelHeight: height)
    }

    /// Pixels per point stored in the image's DPI (144 DPI → 2); 1 when unknown.
    static func pointScale(of data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpi > 0
        else { return 1 }
        return max(1, CGFloat(dpi) / 72)
    }

    /// Encodes a capture as PNG with DPI = 72 × `pointScale`, so Preview and other apps show a
    /// Retina capture at its on-screen point size. `downscaleToOneX` stores one pixel per point.
    static func pngData(from image: CGImage, pointScale: CGFloat, downscaleToOneX: Bool) -> Data? {
        var output = image
        var scale = pointScale
        if downscaleToOneX, pointScale > 1 {
            let width = max(1, Int((CGFloat(image.width) / pointScale).rounded()))
            let height = max(1, Int((CGFloat(image.height) / pointScale).rounded()))
            let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            output = scaled
            scale = 1
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let dpi = 72 * scale
        let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
