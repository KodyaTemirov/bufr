import AppKit
import CoreGraphics
import CoreText
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

// MARK: - Pages that look like real screens

extension ScrollPages {
    enum Overlay {
        /// A header fixed at the top of the view (`opacity` < 1: content shows through)
        case header(height: Int, opacity: CGFloat)
        /// A static column on the left, like a sidebar that doesn't scroll
        case sidebar(width: Int)
        /// A box moving with the page whose content changes every frame (GIF, spinner)
        case animatedBox(pageRect: CGRect)
    }

    private static func context(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// Draws `text` with its top at `top` (page coordinates, top-left origin).
    private static func draw(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat, in context: CGContext, pageHeight: Int) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.textPosition = CGPoint(x: x, y: CGFloat(pageHeight) - top - size * 0.8)
        CTLineDraw(line, context)
    }

    private static let words = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
                                "eiusmod", "tempor", "incididunt", "labore", "magna", "aliqua", "enim", "minim", "veniam", "quis"]

    /// An article: 26 px text at a 40 px pitch, a blank line between paragraphs.
    static func textPage(width: Int = 600, height: Int = 3000, seed: UInt64 = 21, gap: (start: Int, height: Int)? = nil) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = context(width: width, height: height)
        var top = 20
        var lineInParagraph = 0
        while top < height - 40 {
            if let gap, top >= gap.start, top < gap.start + gap.height {
                top = gap.start + gap.height
                continue
            }
            let text = (0..<Int.random(in: 4...8, using: &rng)).map { _ in words.randomElement(using: &rng)! }.joined(separator: " ")
            draw(text, x: 20, top: CGFloat(top), size: 26, in: context, pageHeight: height)
            top += 40
            lineInParagraph += 1
            if lineInParagraph == Int.random(in: 3...6, using: &rng) {
                top += 40
                lineInParagraph = 0
            }
        }
        return context.makeImage()!
    }

    /// A file list: 44 px zebra rows that differ only in a few digits.
    static func tablePage(width: Int = 600, height: Int = 3000) -> CGImage {
        let context = context(width: width, height: height)
        for (index, top) in stride(from: 0, to: height, by: 44).enumerated() {
            if index.isMultiple(of: 2) {
                context.setFillColor(CGColor(gray: 0.94, alpha: 1))
                context.fill(CGRect(x: 0, y: height - top - 44, width: width, height: 44))
            }
            draw(String(format: "Document %d.pdf     12 Sep 2026 at 10:%02d     %d KB", index + 1, index % 60, 40 + index % 7),
                 x: 16, top: CGFloat(top + 10), size: 22, in: context, pageHeight: height)
        }
        return context.makeImage()!
    }

    /// Chat bubbles on both sides.
    static func chatPage(width: Int = 600, height: Int = 3000, seed: UInt64 = 31) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = context(width: width, height: height)
        var top = 16
        var mine = false
        while top < height - 120 {
            let lines = Int.random(in: 1...3, using: &rng)
            let bubbleHeight = 20 + lines * 34
            let bubbleWidth = Int.random(in: 220...420, using: &rng)
            let x = mine ? width - bubbleWidth - 16 : 16
            context.setFillColor(mine ? CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1) : CGColor(gray: 0.9, alpha: 1))
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: height - top - bubbleHeight, width: bubbleWidth, height: bubbleHeight), cornerWidth: 16, cornerHeight: 16, transform: nil))
            context.fillPath()
            for line in 0..<lines {
                let text = (0..<Int.random(in: 2...5, using: &rng)).map { _ in words.randomElement(using: &rng)! }.joined(separator: " ")
                draw(text, x: CGFloat(x + 14), top: CGFloat(top + 10 + line * 34), size: 24, in: context, pageHeight: height)
            }
            top += bubbleHeight + 14
            mine.toggle()
        }
        return context.makeImage()!
    }

    /// The view at `offset` with the given overlays; `frameIndex` changes animated content.
    static func frame(of page: CGImage, offset: Int, height: Int, overlays: [Overlay], frameIndex: Int = 0) -> CGImage {
        let width = page.width
        let context = context(width: width, height: height)
        let crop = page.cropping(to: CGRect(x: 0, y: offset, width: width, height: height))!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rng = SeededGenerator(seed: UInt64(frameIndex) &+ 999)
        for overlay in overlays {
            switch overlay {
            case let .header(headerHeight, opacity):
                context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: opacity))
                context.fill(CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight))
                context.setFillColor(CGColor(gray: 0.2, alpha: 1))
                context.fill(CGRect(x: 20, y: height - headerHeight / 2 - 6, width: 160, height: 12))
            case let .sidebar(sidebarWidth):
                context.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: sidebarWidth, height: height))
                for item in 0..<(height / 36) {
                    context.setFillColor(CGColor(gray: 0.35, alpha: 1))
                    context.fill(CGRect(x: 14, y: height - 24 - item * 36, width: sidebarWidth - 40 - (item * 13) % 50, height: 10))
                }
            case let .animatedBox(pageRect):
                let rect = pageRect.offsetBy(dx: 0, dy: CGFloat(-offset))
                guard rect.maxY > 0, rect.minY < CGFloat(height) else { continue }
                for _ in 0..<40 {
                    let size = CGFloat.random(in: 6...30, using: &rng)
                    let x = CGFloat.random(in: rect.minX...(rect.maxX - size), using: &rng)
                    let y = CGFloat.random(in: rect.minY...(rect.maxY - size), using: &rng)
                    context.setFillColor(CGColor(red: .random(in: 0...1, using: &rng), green: .random(in: 0...1, using: &rng), blue: .random(in: 0...1, using: &rng), alpha: 1))
                    context.fill(CGRect(x: x, y: CGFloat(height) - y - size, width: size, height: size))
                }
            }
        }
        return context.makeImage()!
    }

    /// Rows `range` of two images are identical.
    static func sameRows(_ a: CGImage, _ b: CGImage, _ range: Range<Int>, columns: Range<Int>? = nil) -> Bool {
        let cols = columns ?? 0..<a.width
        let rect = CGRect(x: cols.lowerBound, y: range.lowerBound, width: cols.count, height: range.count)
        guard let x = a.cropping(to: rect), let y = b.cropping(to: rect) else { return false }
        return sameRGBA(x, y)
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
