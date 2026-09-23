import CoreGraphics
import Testing
@testable import Bufr

@MainActor
struct EditorViewModelTests {
    let model: EditorViewModel

    init() {
        let document = AnnotationDocument(baseImageFilename: "x", pixelWidth: 400, pixelHeight: 300, pointScale: 2)
        model = EditorViewModel(document: document, base: TestImages.blank(width: 400, height: 300))
    }

    private func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false) {
        model.pointerDown(at: start, shift: shift, clickCount: 1)
        model.pointerDragged(to: end, shift: shift)
        model.pointerUp(at: end)
    }

    @Test func drawingAnArrowAddsItAndUndoRemovesIt() {
        model.tool = .arrow
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 120, y: 10))

        #expect(model.document.annotations.map(\.shape) == [.arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 120, y: 10))])
        #expect(model.isDirty)

        model.undo()
        #expect(model.document.annotations.isEmpty)
        model.redo()
        #expect(model.document.annotations.count == 1)
    }

    @Test func newShapesUseTheCurrentStyleInPixels() {
        model.tool = .rectangle
        model.weight = .medium
        model.color = .blue
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 50))

        let style = model.document.annotations.first?.style
        #expect(style?.color == .blue)
        #expect(style?.lineWidth == EditorViewModel.Weight.medium.lineWidthPoints * 2) // point scale 2
    }

    @Test func tinyDragAddsNothing() {
        model.tool = .rectangle
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11))

        #expect(model.document.annotations.isEmpty)
    }

    @Test func counterClicksNumberUp() {
        model.tool = .counter
        model.pointerDown(at: CGPoint(x: 50, y: 50), shift: false, clickCount: 1)
        model.pointerUp(at: CGPoint(x: 50, y: 50))
        model.pointerDown(at: CGPoint(x: 150, y: 50), shift: false, clickCount: 1)
        model.pointerUp(at: CGPoint(x: 150, y: 50))

        #expect(model.document.annotations.map(\.shape) == [
            .counter(center: CGPoint(x: 50, y: 50), number: 1),
            .counter(center: CGPoint(x: 150, y: 50), number: 2),
        ])
    }

    @Test func shiftSnapsLinesTo45Degrees() {
        model.tool = .line
        drag(from: .zero, to: CGPoint(x: 100, y: 8), shift: true)

        #expect(model.document.annotations.first?.shape == .line(start: .zero, end: CGPoint(x: 100, y: 0)))
    }

    @Test func selectingAndMovingIsOneUndoStep() {
        model.tool = .filledRectangle
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        let original = model.document.annotations[0].shape

        model.tool = .select
        drag(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 50, y: 40))

        #expect(model.document.annotations[0].shape == .filledRectangle(CGRect(x: 30, y: 20, width: 50, height: 50)))
        #expect(model.selection == [model.document.annotations[0].id])
        model.undo()
        #expect(model.document.annotations[0].shape == original)
    }

    @Test func deleteAndDuplicateSelection() {
        model.tool = .filledRectangle
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        model.selection = [model.document.annotations[0].id]

        model.duplicateSelection()
        #expect(model.document.annotations.count == 2)
        #expect(model.selection == [model.document.annotations[1].id])

        model.deleteSelection()
        #expect(model.document.annotations.count == 1)
    }

    @Test func colorChangeAppliesToTheSelection() {
        model.tool = .ellipse
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        model.selection = [model.document.annotations[0].id]

        model.color = .green

        #expect(model.document.annotations[0].style.color == .green)
    }

    @Test func cropToolSetsTheCrop() {
        model.tool = .crop
        drag(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 220, y: 130))

        #expect(model.document.crop == CGRect(x: 20, y: 30, width: 200, height: 100))
        model.resetCrop()
        #expect(model.document.crop == nil)
    }

    @Test func emptyTextIsRemovedWhenEditingEnds() {
        model.tool = .text
        model.pointerDown(at: CGPoint(x: 40, y: 40), shift: false, clickCount: 1)
        model.pointerUp(at: CGPoint(x: 40, y: 40))
        let id = try? #require(model.editingTextID)

        model.finishEditingText(id: id!, string: "  ")

        #expect(model.document.annotations.isEmpty)
        #expect(model.editingTextID == nil)
    }

    @Test func typedTextIsKept() {
        model.tool = .text
        model.pointerDown(at: CGPoint(x: 40, y: 40), shift: false, clickCount: 1)
        model.pointerUp(at: CGPoint(x: 40, y: 40))

        model.finishEditingText(id: model.editingTextID!, string: "Bug here")

        #expect(model.document.annotations.first?.shape == .text(origin: CGPoint(x: 40, y: 40), string: "Bug here"))
    }

    @Test func cropSnapsToWholePixels() {
        model.tool = .crop
        drag(from: CGPoint(x: 10.4, y: 5.6), to: CGPoint(x: 80.7, y: 60.2))

        let crop = model.document.crop
        #expect(crop == crop?.integral)
    }

    /// Picking a colour for a selected shape keeps its thickness (and a text's size).
    @Test func changingColorKeepsTheSelectionsWeight() {
        model.tool = .rectangle
        model.weight = .thick
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 50))
        model.selection = []
        model.weight = .thin // toolbar now thin, the rectangle still thick
        model.tool = .select
        model.selection = Set(model.document.annotations.map(\.id))

        model.color = .blue

        let style = model.document.annotations.first?.style
        #expect(style?.color == .blue)
        #expect(style?.lineWidth == EditorViewModel.Weight.thick.lineWidthPoints * 2)
    }

    /// Saving runs in the background; an edit made meanwhile is still unsaved afterwards.
    @Test func editDuringASaveStaysUnsaved() {
        model.tool = .rectangle
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 50))
        let beingSaved = model.document
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 150))

        model.markSaved(beingSaved)

        #expect(model.isDirty)
    }

    @Test func undoingBackToTheSavedStateIsClean() {
        model.tool = .rectangle
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 50))
        model.markSaved(model.document)
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 150))

        model.undo()

        #expect(!model.isDirty)
    }
}
