import CoreGraphics
@testable import Bufr

/// Tall test "pages" with rows that never repeat (seeded), cut into frames like a scrolled view.
enum ScrollPages {
    static func page(width: Int = 240, height: Int = 3000, seed: UInt64 = 1, whiteBands: Bool = false) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = 0
        while y < height {
            let blockHeight = Int.random(in: 6...40, using: &rng)
            if whiteBands && Int.random(in: 0..<4, using: &rng) == 0 {
                y += blockHeight * 3 // blank stretch, like page margins between paragraphs
                continue
            }
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let x = Int.random(in: 0..<(width - 20), using: &rng)
                let w = Int.random(in: 10...(width - x), using: &rng)
                context.setFillColor(CGColor(gray: CGFloat.random(in: 0...0.85, using: &rng), alpha: 1))
                context.fill(CGRect(x: x, y: height - y - blockHeight, width: w, height: blockHeight))
            }
            y += blockHeight
        }
        return context.makeImage()!
    }

    /// The viewport at `offset` (top-left origin), optionally with a fixed header/footer painted over it.
    static func frame(of page: CGImage, offset: Int, height: Int, header: Int = 0, footer: Int = 0) -> CGImage {
        let crop = page.cropping(to: CGRect(x: 0, y: offset, width: page.width, height: height))!
        let context = CGContext(data: nil, width: page.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: page.width, height: height))
        if header > 0 {
            context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: height - header, width: page.width, height: header))
        }
        if footer > 0 {
            context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: page.width, height: footer))
        }
        return context.makeImage()!
    }

    static func sameRGBA(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, let x = RGBABuffer(a), let y = RGBABuffer(b) else { return false }
        return x.bytes == y.bytes
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
