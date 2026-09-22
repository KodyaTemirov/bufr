import CoreGraphics
import Testing
@testable import Bufr

struct ScreenPinGeometryTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    /// A 5K capture (2560×1440 pt) pinned on a 1440 pt wide screen shrinks to 80% of it.
    @Test func largeImageIsFittedKeepingAspect() {
        let frame = ScreenPinGeometry.initialFrame(
            imageSize: CGSize(width: 2560, height: 1440), sourceRect: nil,
            mouse: CGPoint(x: 720, y: 437), visibleFrame: visible
        )

        #expect(frame.size == CGSize(width: 1152, height: 648))
        #expect(visible.contains(frame))
    }

    @Test func smallImageKeepsItsSizeAndIsCentredOnMouse() {
        let frame = ScreenPinGeometry.initialFrame(
            imageSize: CGSize(width: 200, height: 100), sourceRect: nil,
            mouse: CGPoint(x: 500, y: 400), visibleFrame: visible
        )

        #expect(frame == CGRect(x: 400, y: 350, width: 200, height: 100))
    }

    @Test func pinFromCaptureOpensWhereTheContentWas() {
        let source = CGRect(x: 100, y: 120, width: 300, height: 200)

        let frame = ScreenPinGeometry.initialFrame(
            imageSize: CGSize(width: 300, height: 200), sourceRect: source,
            mouse: .zero, visibleFrame: visible
        )

        #expect(frame == source)
    }

    @Test func frameNearEdgeIsPulledOnScreen() {
        let frame = ScreenPinGeometry.initialFrame(
            imageSize: CGSize(width: 200, height: 100), sourceRect: nil,
            mouse: CGPoint(x: 1430, y: 5), visibleFrame: visible
        )

        #expect(frame == CGRect(x: 1240, y: 0, width: 200, height: 100))
    }

    @Test func scrollChangesOpacityWithinLimits() {
        #expect(ScreenPinGeometry.opacity(1, scrollDelta: -50) == 0.5)
        #expect(ScreenPinGeometry.opacity(0.3, scrollDelta: -50) == ScreenPinGeometry.minimumOpacity)
        #expect(ScreenPinGeometry.opacity(0.9, scrollDelta: 50) == 1)
    }
}
