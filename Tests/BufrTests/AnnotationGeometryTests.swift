import CoreGraphics
import Testing
@testable import Bufr

struct AnnotationGeometryTests {
    let style = AnnotationStyle(color: .red, lineWidth: 4, fontSize: 30)

    private func annotation(_ shape: AnnotationShape) -> Annotation {
        Annotation(shape: shape, style: style)
    }

    @Test func arrowIsHitAlongItsShaftOnly() {
        let arrow = annotation(.arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 10)))

        #expect(AnnotationGeometry.hitTest(arrow, at: CGPoint(x: 60, y: 13), tolerance: 3))
        #expect(!AnnotationGeometry.hitTest(arrow, at: CGPoint(x: 60, y: 40), tolerance: 3))
    }

    @Test func outlinedRectangleIsHitOnItsBorderNotInside() {
        let rect = annotation(.rectangle(CGRect(x: 10, y: 10, width: 100, height: 60)))

        #expect(AnnotationGeometry.hitTest(rect, at: CGPoint(x: 10, y: 40), tolerance: 3))
        #expect(!AnnotationGeometry.hitTest(rect, at: CGPoint(x: 60, y: 40), tolerance: 3))
    }

    @Test func filledShapesAndEffectsAreHitInside() {
        #expect(AnnotationGeometry.hitTest(annotation(.filledRectangle(CGRect(x: 0, y: 0, width: 50, height: 50))), at: CGPoint(x: 25, y: 25), tolerance: 2))
        #expect(AnnotationGeometry.hitTest(annotation(.pixelate(CGRect(x: 0, y: 0, width: 50, height: 50))), at: CGPoint(x: 25, y: 25), tolerance: 2))
    }

    @Test func counterIsHitInsideItsCircle() {
        let counter = annotation(.counter(center: CGPoint(x: 50, y: 50), number: 1))

        #expect(AnnotationGeometry.hitTest(counter, at: CGPoint(x: 55, y: 55), tolerance: 2))
        #expect(!AnnotationGeometry.hitTest(counter, at: CGPoint(x: 90, y: 90), tolerance: 2))
    }

    @Test func topmostAnnotationWinsWhenOverlapping() {
        let bottom = annotation(.filledRectangle(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let top = annotation(.filledRectangle(CGRect(x: 40, y: 40, width: 20, height: 20)))
        let document = AnnotationDocument(baseImageFilename: "a", pixelWidth: 100, pixelHeight: 100, pointScale: 1, annotations: [bottom, top])

        #expect(document.topmost(at: CGPoint(x: 50, y: 50), tolerance: 2)?.id == top.id)
        #expect(document.topmost(at: CGPoint(x: 10, y: 10), tolerance: 2)?.id == bottom.id)
        #expect(document.topmost(at: CGPoint(x: 500, y: 500), tolerance: 2) == nil)
    }

    @Test func rectangleResizesByCornerHandle() {
        let resized = AnnotationGeometry.resized(
            .rectangle(CGRect(x: 10, y: 10, width: 40, height: 30)),
            handle: .rect(.maxXMaxY), to: CGPoint(x: 80, y: 70), minimumSize: 4
        )

        #expect(resized == .rectangle(CGRect(x: 10, y: 10, width: 70, height: 60)))
    }

    @Test func arrowEndpointsAreHandles() {
        let arrow = AnnotationShape.arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 50))

        #expect(AnnotationGeometry.resized(arrow, handle: .end, to: CGPoint(x: 90, y: 20), minimumSize: 4)
            == .arrow(start: .zero, end: CGPoint(x: 90, y: 20)))
        #expect(AnnotationGeometry.handles(for: arrow).map(\.handle) == [.start, .end])
    }

    @Test func boundsIncludeStrokeWidth() {
        let bounds = AnnotationGeometry.bounds(of: annotation(.line(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 10))))

        #expect(bounds.minY <= 8)
        #expect(bounds.maxX >= 62)
    }

    @Test func arrowPathReachesBothEnds() {
        let path = AnnotationGeometry.arrowPath(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 20), width: 6)
        let box = path.boundingBox

        #expect(abs(box.minX - 10) < 1)
        #expect(abs(box.maxX - 110) < 1)
        #expect(path.contains(CGPoint(x: 105, y: 20)))
    }

    /// ⇧ while drawing a line or arrow snaps it to 45° steps.
    @Test func angleSnapsTo45Degrees() {
        let snapped = AnnotationGeometry.snappedEnd(from: .zero, to: CGPoint(x: 100, y: 10))

        #expect(snapped == CGPoint(x: 100, y: 0))
        let diagonal = AnnotationGeometry.snappedEnd(from: .zero, to: CGPoint(x: 100, y: 90))
        #expect(abs(diagonal.x - diagonal.y) < 0.001)
    }

    /// Clicks pick what the user sees on top: arrows and shapes are drawn over effects and
    /// spotlights whatever order they were added in.
    @Test func vectorShapesWinOverLaterEffects() {
        let arrow = annotation(.arrow(start: CGPoint(x: 10, y: 30), end: CGPoint(x: 110, y: 30)))
        let pixelate = annotation(.pixelate(CGRect(x: 0, y: 0, width: 200, height: 100)))
        let document = AnnotationDocument(baseImageFilename: "b", pixelWidth: 200, pixelHeight: 100, pointScale: 1, annotations: [arrow, pixelate])

        #expect(document.topmost(at: CGPoint(x: 60, y: 31), tolerance: 3)?.id == arrow.id)
        #expect(document.topmost(at: CGPoint(x: 60, y: 80), tolerance: 3)?.id == pixelate.id)
    }

    /// A spotlight is selected by its edge; shapes inside it stay clickable.
    @Test func spotlightInteriorDoesNotCaptureClicks() {
        let rect = annotation(.rectangle(CGRect(x: 50, y: 30, width: 60, height: 40)))
        let spotlight = annotation(.spotlight(CGRect(x: 20, y: 10, width: 160, height: 80)))
        let document = AnnotationDocument(baseImageFilename: "b", pixelWidth: 200, pixelHeight: 100, pointScale: 1, annotations: [rect, spotlight])

        #expect(document.topmost(at: CGPoint(x: 50, y: 50), tolerance: 3)?.id == rect.id)
        #expect(document.topmost(at: CGPoint(x: 150, y: 50), tolerance: 3) == nil)
        #expect(document.topmost(at: CGPoint(x: 20, y: 50), tolerance: 3)?.id == spotlight.id)
    }
}
