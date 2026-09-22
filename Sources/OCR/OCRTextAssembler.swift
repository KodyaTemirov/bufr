import CoreGraphics

/// Rebuilds reading order from recognized text boxes: rows top to bottom, boxes on a row
/// left to right, and a blank line where the vertical gap suggests a new paragraph.
enum OCRTextAssembler {
    struct Line: Equatable, Sendable {
        let text: String
        /// Normalized, bottom-left origin (Vision's convention)
        let box: CGRect
    }

    private struct Row {
        var lines: [Line]
        var midY: CGFloat
        var minY: CGFloat
        var maxY: CGFloat
        var height: CGFloat
    }

    static func text(from lines: [Line]) -> String {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }

        var rows: [Row] = []
        for line in sorted {
            if var row = rows.last, abs(line.box.midY - row.midY) < min(line.box.height, row.height) * 0.5 {
                row.lines.append(line)
                row.minY = min(row.minY, line.box.minY)
                row.maxY = max(row.maxY, line.box.maxY)
                row.height = max(row.height, line.box.height)
                rows[rows.count - 1] = row
            } else {
                rows.append(Row(lines: [line], midY: line.box.midY, minY: line.box.minY, maxY: line.box.maxY, height: line.box.height))
            }
        }

        var result = ""
        for (index, row) in rows.enumerated() {
            let rowText = row.lines.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
            if index > 0 {
                let previous = rows[index - 1]
                let gap = previous.minY - row.maxY
                result += gap > (previous.height + row.height) / 2 * 0.9 ? "\n\n" : "\n"
            }
            result += rowText
        }
        return result
    }
}
