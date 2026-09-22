import CoreGraphics
import Testing
@testable import Bufr

/// Boxes are normalized with a bottom-left origin, like Vision's.
struct OCRTextAssemblerTests {
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05) -> OCRTextAssembler.Line {
        OCRTextAssembler.Line(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func singleLine() {
        #expect(OCRTextAssembler.text(from: [line("Hello", x: 0.1, y: 0.5)]) == "Hello")
    }

    @Test func rowsGoTopToBottomWhateverTheInputOrder() {
        let text = OCRTextAssembler.text(from: [
            line("second", x: 0.1, y: 0.44),
            line("first", x: 0.1, y: 0.5),
        ])

        #expect(text == "first\nsecond")
    }

    @Test func boxesOnTheSameRowJoinLeftToRight() {
        let text = OCRTextAssembler.text(from: [
            line("world", x: 0.5, y: 0.5),
            line("Hello", x: 0.1, y: 0.505),
        ])

        #expect(text == "Hello world")
    }

    @Test func largeVerticalGapStartsAParagraph() {
        let text = OCRTextAssembler.text(from: [
            line("Title", x: 0.1, y: 0.8),
            line("Body", x: 0.1, y: 0.5),
        ])

        #expect(text == "Title\n\nBody")
    }

    @Test func emptyTextIsIgnored() {
        #expect(OCRTextAssembler.text(from: [line("  ", x: 0, y: 0.5)]) == "")
    }

    @Test func sideBySideColumnsAreReadOneAfterAnother() {
        let rows: [CGFloat] = [0.8, 0.72, 0.64, 0.56]
        let lines = rows.enumerated().flatMap { index, y in
            [line("L\(index + 1)", x: 0.05, y: y, width: 0.4), line("R\(index + 1)", x: 0.55, y: y, width: 0.4)]
        }

        #expect(OCRTextAssembler.text(from: lines) == "L1\nL2\nL3\nL4\n\nR1\nR2\nR3\nR4")
    }

    @Test func fullWidthTitleComesBeforeTheColumns() {
        let rows: [CGFloat] = [0.7, 0.62, 0.54]
        let lines = [line("Title", x: 0.05, y: 0.9, width: 0.9)] + rows.enumerated().flatMap { index, y in
            [line("L\(index + 1)", x: 0.05, y: y, width: 0.4), line("R\(index + 1)", x: 0.55, y: y, width: 0.4)]
        }

        #expect(OCRTextAssembler.text(from: lines) == "Title\n\nL1\nL2\nL3\n\nR1\nR2\nR3")
    }

    /// Settings screens and tables: a short label and its value stay on one line.
    @Test func labelValueRowsStayTogether() {
        let lines = [
            line("Name", x: 0.05, y: 0.8, width: 0.08), line("John", x: 0.5, y: 0.8, width: 0.2),
            line("Email", x: 0.05, y: 0.72, width: 0.08), line("john@example.com", x: 0.5, y: 0.72, width: 0.3),
            line("City", x: 0.05, y: 0.64, width: 0.08), line("Tashkent", x: 0.5, y: 0.64, width: 0.2),
        ]

        #expect(OCRTextAssembler.text(from: lines) == "Name John\nEmail john@example.com\nCity Tashkent")
    }
}
