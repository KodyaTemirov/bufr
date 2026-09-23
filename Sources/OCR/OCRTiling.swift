import CoreGraphics
import Foundation

/// Long images (scrolling captures) are recognized in overlapping strips: shrunk to Vision's
/// working size as a whole, their letters would become a few pixels tall.
enum OCRTiling {
    /// Strips for an image of this pixel size: one (the whole image) unless it is taller than
    /// `maxStrip` and half again as tall as it is wide — Vision misses lines on taller images.
    static func tiles(width: Int, height: Int, maxStrip: Int = 2048, overlap: Int = 200) -> [CGRect] {
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 0, height > maxStrip, Double(height) > Double(width) * 1.5 else { return [whole] }
        var tiles: [CGRect] = []
        var y = 0
        while true {
            let stripHeight = min(maxStrip, height - y)
            tiles.append(CGRect(x: 0, y: y, width: width, height: stripHeight))
            if y + stripHeight >= height { break }
            y += maxStrip - overlap
        }
        return tiles
    }

    /// The text of all strips as one image. A line in the overlap of two strips is read by
    /// both — possibly differently, if an edge cuts it — so each line is taken from the strip
    /// on whose side of the overlap's middle its centre lies (where it is whole). Line boxes
    /// are Vision's: normalized to their strip, bottom-left origin.
    static func assemble(_ strips: [(rect: CGRect, lines: [OCRTextAssembler.Line])], imageHeight: Int) -> String {
        guard strips.count > 1 else { return OCRTextAssembler.text(from: strips.first?.lines ?? []) }
        let height = CGFloat(imageHeight)
        var kept: [OCRTextAssembler.Line] = []
        for (index, strip) in strips.enumerated() {
            let ownTop = index == 0 ? 0 : (strip.rect.minY + strips[index - 1].rect.maxY) / 2
            let ownBottom = index == strips.count - 1 ? height : (strips[index + 1].rect.minY + strip.rect.maxY) / 2
            for line in strip.lines {
                let top = strip.rect.minY + (1 - line.box.maxY) * strip.rect.height
                let bottom = strip.rect.minY + (1 - line.box.minY) * strip.rect.height
                let centre = (top + bottom) / 2
                guard centre >= ownTop, centre < ownBottom else { continue }
                // Normalized to the whole image, still bottom-left origin
                kept.append(OCRTextAssembler.Line(
                    text: line.text,
                    box: CGRect(x: line.box.minX, y: 1 - bottom / height, width: line.box.width, height: (bottom - top) / height)
                ))
            }
        }
        return OCRTextAssembler.text(from: kept)
    }
}
