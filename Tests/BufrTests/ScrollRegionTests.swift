import CoreGraphics
import Testing
@testable import Bufr

struct ScrollRegionTests {
    private func region(scale: CGFloat) -> ScrollRegion {
        ScrollRegion(
            displayID: 1, localRect: CGRect(x: 10, y: 10, width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), pointScale: scale,
            sourceAppId: nil, sourceAppName: nil
        )
    }

    /// Review Focus 4: frames are as many pixels as that display has per point.
    @Test func pixelSizeUsesTheRegionsDisplayScale() {
        #expect(region(scale: 2).pixelSize == CGSize(width: 600, height: 400))
        #expect(region(scale: 1).pixelSize == CGSize(width: 300, height: 200))
    }

    @Test func cocoaRectIsOnItsScreen() {
        #expect(region(scale: 2).cocoaRect == CGRect(x: 10, y: 690, width: 300, height: 200))
    }

    /// A window picked with Space becomes the region, cut to the screen it is on.
    @Test func windowRegionIsClippedToItsScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let local = ScrollRegion.localRect(ofWindow: CGRect(x: -50, y: 100, width: 400, height: 2000), screenFrame: primary, primaryHeight: 900)
        #expect(local == CGRect(x: 0, y: 100, width: 350, height: 800))

        // Second display to the right, taller than the primary (Cocoa y 0…1080 → CG y -180…900)
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let onSecondary = ScrollRegion.localRect(ofWindow: CGRect(x: 1500, y: -100, width: 500, height: 400), screenFrame: secondary, primaryHeight: 900)
        #expect(onSecondary == CGRect(x: 60, y: 80, width: 500, height: 400))
    }
}
