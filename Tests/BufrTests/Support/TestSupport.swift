import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestSupport {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum TestImages {
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    /// Solid red image; different sizes produce different bytes (useful for dedup tests).
    static func cgImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encoded(_ type: UTType, width: Int, height: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage(width: width, height: height), nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png(width: Int = 4, height: Int = 3) -> Data { encoded(.png, width: width, height: height) }
    static func tiff(width: Int = 4, height: Int = 3) -> Data { encoded(.tiff, width: width, height: height) }

    /// Black text on white, large enough for Vision.
    static func text(_ string: String, width: Int = 900, height: Int = 200, fontSize: CGFloat = 56) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: string,
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        ))
        context.textPosition = CGPoint(x: 30, y: CGFloat(height) / 2 - fontSize / 3)
        CTLineDraw(line, context)
        return context.makeImage()!
    }

    static func qrCode(_ message: String) -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        // Quiet zone around the code
        let padded = image.composited(over: CIImage(color: .white).cropped(to: image.extent.insetBy(dx: -40, dy: -40)))
        return CIContext().createCGImage(padded, from: padded.extent)!
    }

    static func blank(width: Int = 400, height: Int = 200) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
