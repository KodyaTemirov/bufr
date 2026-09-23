import CoreGraphics
import Foundation

/// 8-bit RGBA pixels (premultiplied, top row first) that rows can be copied out of and
/// appended to cheaply — the scrolling capture's growing canvas.
struct RGBABuffer {
    let width: Int
    private(set) var height: Int
    private(set) var bytes: [UInt8]
    let colorSpace: CGColorSpace

    var bytesPerRow: Int { width * 4 }

    init(width: Int, colorSpace: CGColorSpace = RGBABuffer.sRGB) {
        self.width = width
        self.height = 0
        self.bytes = []
        self.colorSpace = colorSpace
    }

    /// The image's pixels in its own RGB colour space (sRGB otherwise).
    init?(_ image: CGImage) {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? RGBABuffer.sRGB
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
        self.colorSpace = space
    }

    func rows(_ range: Range<Int>) -> ArraySlice<UInt8> {
        bytes[(range.lowerBound * bytesPerRow)..<(range.upperBound * bytesPerRow)]
    }

    mutating func append(rows: ArraySlice<UInt8>) {
        bytes.append(contentsOf: rows)
        height += rows.count / bytesPerRow
    }

    func makeImage() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
}
