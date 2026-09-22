import CoreGraphics

/// Rebuilds reading order from recognized text boxes: rows top to bottom, boxes on a row
/// left to right, and a blank line where the vertical gap suggests a new paragraph.
/// Two side-by-side text columns are read one after the other rather than interleaved.
enum OCRTextAssembler {
    struct Line: Equatable, Sendable {
        let text: String
        /// Normalized, bottom-left origin (Vision's convention)
        let box: CGRect
    }

    private struct Row {
        var lines: [Line]
        /// Where the row started; later boxes join when their centers are close to it
        var midY: CGFloat

        init(lines: [Line]) {
            self.lines = lines
            self.midY = lines[0].box.midY
        }

        var minY: CGFloat { lines.map(\.box.minY).min() ?? 0 }
        var maxY: CGFloat { lines.map(\.box.maxY).max() ?? 0 }
        var height: CGFloat { lines.map(\.box.height).max() ?? 0 }
    }

    /// Narrower empty strips are word spacing, not a gutter between columns
    private static let minimumGutter: CGFloat = 0.02
    /// Rows with text on both sides before a strip counts as a column gutter
    private static let minimumColumnRows = 3

    static func text(from lines: [Line]) -> String {
        let rows = makeRows(lines)

        var blocks: [[Row]] = []
        var plain: [Row] = []
        var index = 0
        while index < rows.count {
            if let columns = columnRun(in: rows, from: index) {
                if !plain.isEmpty {
                    blocks.append(plain)
                    plain = []
                }
                blocks.append(columns.left)
                blocks.append(columns.right)
                index = columns.end
            } else {
                plain.append(rows[index])
                index += 1
            }
        }
        if !plain.isEmpty {
            blocks.append(plain)
        }
        return blocks.map(joined).joined(separator: "\n\n")
    }

    private static func makeRows(_ lines: [Line]) -> [Row] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }

        var rows: [Row] = []
        for line in sorted {
            if let row = rows.last, abs(line.box.midY - row.midY) < min(line.box.height, row.height) * 0.5 {
                rows[rows.count - 1].lines.append(line)
            } else {
                rows.append(Row(lines: [line]))
            }
        }
        return rows
    }

    private static func joined(_ rows: [Row]) -> String {
        var result = ""
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let previous = rows[index - 1]
                let gap = previous.minY - row.maxY
                result += gap > (previous.height + row.height) / 2 * 0.9 ? "\n\n" : "\n"
            }
            result += row.lines.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
        return result
    }

    /// Consecutive rows, starting at `start`, split by one empty vertical strip into two text
    /// columns. A label/value layout (settings, forms, receipts) also has such a strip, but
    /// there it is wide compared to the text beside it, and those rows stay rows.
    private static func columnRun(in rows: [Row], from start: Int) -> (left: [Row], right: [Row], end: Int)? {
        let first = rows[start].lines.sorted { $0.box.minX < $1.box.minX }
        var gaps: [(lower: CGFloat, upper: CGFloat)] = []
        for (left, right) in zip(first, first.dropFirst()) where right.box.minX - left.box.maxX >= minimumGutter {
            gaps.append((left.box.maxX, right.box.minX))
        }
        gaps.sort { $0.upper - $0.lower > $1.upper - $1.lower }

        for gap in gaps {
            var lower = gap.lower
            var upper = gap.upper
            var end = start
            var twoSided = 0
            scan: while end < rows.count {
                let split = (lower + upper) / 2
                var rowLower = lower
                var rowUpper = upper
                var hasLeft = false
                var hasRight = false
                for line in rows[end].lines {
                    if line.box.maxX <= split {
                        rowLower = max(rowLower, line.box.maxX)
                        hasLeft = true
                    } else if line.box.minX >= split {
                        rowUpper = min(rowUpper, line.box.minX)
                        hasRight = true
                    } else {
                        break scan // a line crosses the strip: a heading or a full-width paragraph
                    }
                }
                guard rowUpper - rowLower >= minimumGutter else { break }
                lower = rowLower
                upper = rowUpper
                if hasLeft && hasRight {
                    twoSided += 1
                }
                end += 1
            }
            guard twoSided >= minimumColumnRows else { continue }

            let split = (lower + upper) / 2
            let run = rows[start..<end]
            let left = run.map { $0.lines.filter { $0.box.maxX <= split } }.filter { !$0.isEmpty }.map(Row.init)
            let right = run.map { $0.lines.filter { $0.box.minX >= split } }.filter { !$0.isEmpty }.map(Row.init)
            let narrowerColumn = min(medianWidth(left), medianWidth(right))
            guard upper - lower < narrowerColumn * 0.5 else { continue }
            return (left, right, end)
        }
        return nil
    }

    private static func medianWidth(_ rows: [Row]) -> CGFloat {
        let widths = rows.flatMap { $0.lines.map(\.box.width) }.sorted()
        return widths.isEmpty ? 0 : widths[widths.count / 2]
    }
}
