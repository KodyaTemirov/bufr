import CoreGraphics
import Testing
@testable import Bufr

struct ScreenGeometryTests {
    @Test func cgRectFromCocoaOnPrimary() {
        let cocoa = CGRect(x: 100, y: 700, width: 200, height: 100)

        #expect(ScreenGeometry.cgRect(fromCocoa: cocoa, primaryHeight: 900) == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    /// A 1920×1080 display placed above and to the left of a 900 pt tall primary display.
    @Test func secondaryDisplayLeftAndAbove() {
        let cocoa = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        let cg = ScreenGeometry.cgRect(fromCocoa: cocoa, primaryHeight: 900)

        #expect(cg == CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        #expect(ScreenGeometry.cocoaRect(fromCG: cg, primaryHeight: 900) == cocoa)
    }

    @Test func cgPointFromCocoa() {
        #expect(ScreenGeometry.cgPoint(fromCocoa: CGPoint(x: 5, y: 890), primaryHeight: 900) == CGPoint(x: 5, y: 10))
    }

    @Test func flippedRectInView() {
        let bottomLeft = CGRect(x: 10, y: 20, width: 30, height: 40)

        #expect(ScreenGeometry.flipped(bottomLeft, height: 100) == CGRect(x: 10, y: 40, width: 30, height: 40))
    }

    @Test func pixelRectOnRetina() {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: CGRect(x: 10, y: 20, width: 30, height: 40),
            displayPointSize: CGSize(width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        #expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    /// "More Space" style scaling: 1.5 pixels per point. Edges round outward.
    @Test func pixelRectOnFractionalScale() {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: CGRect(x: 1, y: 1, width: 1, height: 1),
            displayPointSize: CGSize(width: 1280, height: 800),
            imagePixelSize: CGSize(width: 1920, height: 1200)
        )

        #expect(pixels == CGRect(x: 1, y: 1, width: 2, height: 2))
    }

    @Test func pixelRectIsClampedToImage() {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: CGRect(x: -10, y: 890, width: 50, height: 50),
            displayPointSize: CGSize(width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        #expect(pixels == CGRect(x: 0, y: 1780, width: 80, height: 20))
    }

    @Test func pixelRectOutsideImageIsNull() {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: CGRect(x: 2000, y: 0, width: 10, height: 10),
            displayPointSize: CGSize(width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        #expect(pixels.isNull)
    }
}
