import CoreGraphics
import Foundation

/// Long images (scrolling captures) are recognized in overlapping strips: shrunk to Vision's
/// working size as a whole, their letters would become a few pixels tall.
enum OCRTiling {
    /// Strips for an image of this pixel size; one strip (the whole image) unless it is taller
    /// than `maxSide` and at least twice as tall as it is wide.
    static func tiles(width: Int, height: Int, maxSide: Int = 6144, tileHeight: Int = 4096, overlap: Int = 200) -> [CGRect] {
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 0, height > maxSide, height >= 2 * width else { return [whole] }
        var tiles: [CGRect] = []
        var y = 0
        while true {
            let stripHeight = min(tileHeight, height - y)
            tiles.append(CGRect(x: 0, y: y, width: width, height: stripHeight))
            if y + stripHeight >= height { break }
            y += tileHeight - overlap
        }
        return tiles
    }

    /// Joins the strips' texts; lines a strip repeats from the end of the previous one (they
    /// were in the overlap) appear once.
    static func join(_ texts: [String], overlapLines: Int = 6) -> String {
        var lines: [String] = []
        for text in texts where !text.isEmpty {
            let next = text.components(separatedBy: "\n")
            var repeated = 0
            for count in stride(from: min(overlapLines, next.count, lines.count), to: 0, by: -1)
            where next.prefix(count).map(trimmed) == lines.suffix(count).map(trimmed) {
                repeated = count
                break
            }
            lines.append(contentsOf: next.dropFirst(repeated))
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }
}
