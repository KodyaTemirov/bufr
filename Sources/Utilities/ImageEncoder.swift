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
}
