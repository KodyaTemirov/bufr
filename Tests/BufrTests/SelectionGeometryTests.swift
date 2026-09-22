import CoreGraphics
import Testing
@testable import Bufr

struct SelectionGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test func dragInAnyDirectionNormalizes() {
        let forward = SelectionGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30),
                                             square: false, fromCenter: false, bounds: bounds)
        let backward = SelectionGeometry.rect(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 10, y: 10),
                                              square: false, fromCenter: false, bounds: bounds)

        #expect(forward == CGRect(x: 10, y: 10, width: 40, height: 20))
        #expect(backward == forward)
    }

    @Test func squareUsesLongerSide() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30),
                                          square: true, fromCenter: false, bounds: bounds)

        #expect(rect == CGRect(x: 10, y: 10, width: 40, height: 40))
    }

    @Test func squareKeepsDragDirection() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 50, y: 30),
                                          square: true, fromCenter: false, bounds: bounds)

        #expect(rect == CGRect(x: 30, y: 30, width: 30, height: 30))
    }

    @Test func fromCenterGrowsAroundStart() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 70),
                                          square: false, fromCenter: true, bounds: bounds)

        #expect(rect == CGRect(x: 40, y: 30, width: 20, height: 40))
    }

    @Test func clampedToBounds() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 90, y: 90), to: CGPoint(x: 150, y: 150),
                                          square: false, fromCenter: false, bounds: bounds)

        #expect(rect == CGRect(x: 90, y: 90, width: 10, height: 10))
    }

    @Test func movedStaysInsideBounds() {
        let moved = SelectionGeometry.moved(CGRect(x: 80, y: 80, width: 20, height: 20),
                                            by: CGSize(width: 30, height: -100), within: bounds)

        #expect(moved == CGRect(x: 80, y: 0, width: 20, height: 20))
    }

    // MARK: - Handles (all-in-one mode)

    let rect = CGRect(x: 20, y: 20, width: 40, height: 30)

    @Test func handleHitTesting() {
        #expect(SelectionGeometry.handle(at: CGPoint(x: 61, y: 49), in: rect, tolerance: 4) == .maxXMaxY)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 40, y: 20), in: rect, tolerance: 4) == .midXMinY)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 40, y: 35), in: rect, tolerance: 4) == nil)
    }

    @Test func resizeByCornerHandle() {
        let resized = SelectionGeometry.resized(rect, handle: .maxXMaxY, to: CGPoint(x: 80, y: 70), bounds: bounds, minimumSize: 4)

        #expect(resized == CGRect(x: 20, y: 20, width: 60, height: 50))
    }

    @Test func resizeByEdgeHandleKeepsOtherAxis() {
        let resized = SelectionGeometry.resized(rect, handle: .minXMidY, to: CGPoint(x: 10, y: 90), bounds: bounds, minimumSize: 4)

        #expect(resized == CGRect(x: 10, y: 20, width: 50, height: 30))
    }

    /// Dragging a handle past the opposite edge stops at the minimum size instead of flipping.
    @Test func resizeThroughOppositeEdgeKeepsMinimumSize() {
        let resized = SelectionGeometry.resized(rect, handle: .maxXMidY, to: CGPoint(x: 0, y: 35), bounds: bounds, minimumSize: 4)

        #expect(resized == CGRect(x: 20, y: 20, width: 4, height: 30))
    }

    @Test func resizeIsClampedToBounds() {
        let resized = SelectionGeometry.resized(rect, handle: .maxXMaxY, to: CGPoint(x: 500, y: 500), bounds: bounds, minimumSize: 4)

        #expect(resized == CGRect(x: 20, y: 20, width: 80, height: 80))
    }

    @Test func nudgeMovesWithinBounds() {
        #expect(SelectionGeometry.nudged(rect, dx: 10, dy: -5, bounds: bounds) == CGRect(x: 30, y: 15, width: 40, height: 30))
        #expect(SelectionGeometry.nudged(rect, dx: 100, dy: 0, bounds: bounds).maxX == 100)
    }

    /// ⌥+arrows resize from the right and bottom edges; the top-left corner stays put
    /// (bottom = minY in the overlay's bottom-left coordinates).
    @Test func keyboardResizeKeepsTopLeftCorner() {
        let grown = SelectionGeometry.grown(rect, dWidth: 5, dHeight: 10, bounds: bounds, minimumSize: 4)
        let shrunk = SelectionGeometry.grown(rect, dWidth: -100, dHeight: -100, bounds: bounds, minimumSize: 4)

        #expect(grown == CGRect(x: 20, y: 10, width: 45, height: 40))
        #expect(shrunk == CGRect(x: 20, y: 46, width: 4, height: 4))
    }
}
