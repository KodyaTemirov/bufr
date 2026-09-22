import AppKit

enum QuickAccessThumbnail {
    /// Twice the card width: sharp on Retina, tiny next to a full display frame
    static let maxPixelSize = 480

    /// A downsampled, independent copy — a crop of the frozen frame would keep the whole
    /// display image (tens of MB on 5K) alive for as long as the card exists.
    static func make(from image: CGImage, pointScale: CGFloat) -> NSImage {
        let scale = min(1, CGFloat(maxPixelSize) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let pointSize = CGSize(width: CGFloat(image.width) / pointScale, height: CGFloat(image.height) / pointScale)

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: pointSize)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return NSImage(size: pointSize) }
        return NSImage(cgImage: small, size: pointSize)
    }
}
