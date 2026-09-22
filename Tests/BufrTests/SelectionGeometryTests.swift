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
}
