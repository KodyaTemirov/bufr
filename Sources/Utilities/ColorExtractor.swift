import AppKit
import Foundation

struct ColorExtractor {
    // Matches: #RGB, #RRGGBB, #RRGGBBAA
    private static let hexPattern = #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#

    // Matches: rgb(r, g, b), rgba(r, g, b, a)
    private static let rgbPattern = #"^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*(,\s*[\d.]+\s*)?\)$"#

    // Matches: hsl(h, s%, l%), hsla(h, s%, l%, a)
    private static let hslPattern = #"^hsla?\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*(,\s*[\d.]+\s*)?\)$"#

    static func isColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 50 else { return false }

        return trimmed.range(of: hexPattern, options: .regularExpression) != nil
            || trimmed.range(of: rgbPattern, options: .regularExpression) != nil
            || trimmed.range(of: hslPattern, options: .regularExpression) != nil
    }

    /// Returns the average saturated color from an NSImage (skips transparent/gray pixels).
    static func dominantColor(from image: NSImage) -> NSColor? {
        let size = NSSize(width: 16, height: 16)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0, count: CGFloat = 0

        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                guard let color = bitmapRep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }
                guard color.alphaComponent > 0.3 else { continue }
                let saturation = max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent)
                guard saturation > 0.1 else { continue }
                totalR += color.redComponent
                totalG += color.greenComponent
                totalB += color.blueComponent
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return NSColor(red: totalR / count, green: totalG / count, blue: totalB / count, alpha: 1)
    }

    static func parseHexColor(_ hex: String) -> NSColor? {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed

        var rgb: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&rgb) else { return nil }

        switch trimmed.count {
        case 3:
            let r = CGFloat((rgb >> 8) & 0xF) / 15.0
            let g = CGFloat((rgb >> 4) & 0xF) / 15.0
            let b = CGFloat(rgb & 0xF) / 15.0
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        case 6:
            let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
            let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
            let b = CGFloat(rgb & 0xFF) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        case 8:
            let r = CGFloat((rgb >> 24) & 0xFF) / 255.0
            let g = CGFloat((rgb >> 16) & 0xFF) / 255.0
            let b = CGFloat((rgb >> 8) & 0xFF) / 255.0
            let a = CGFloat(rgb & 0xFF) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }
}
