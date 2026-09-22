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
}
