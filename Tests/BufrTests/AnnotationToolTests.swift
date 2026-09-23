import Testing
@testable import Bufr

struct AnnotationToolTests {
    /// The toolbar shows the tools in groups; none may be missing or shown twice.
    @Test func groupsShowEveryToolOnce() {
        let grouped = AnnotationTool.groups.flatMap { $0 }

        #expect(grouped.count == AnnotationTool.allCases.count)
        #expect(Set(grouped) == Set(AnnotationTool.allCases))
    }

    /// The options row offers only what changes the result of that tool.
    @Test func optionsMatchWhatTheToolDraws() {
        #expect(AnnotationTool.arrow.options == [.color, .thickness])
        #expect(AnnotationTool.filledRectangle.options == [.color])
        #expect(AnnotationTool.highlighter.options == [.color])
        #expect(AnnotationTool.text.options == [.color, .size])
        #expect(AnnotationTool.counter.options == [.color, .size])
        #expect(AnnotationTool.pixelate.options.isEmpty)
        #expect(AnnotationTool.crop.options.isEmpty)
    }
}
