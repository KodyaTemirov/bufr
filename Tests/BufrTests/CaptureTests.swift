import CoreGraphics
import Foundation
import Testing
@testable import Bufr

/// Reads the RGBA of the top-left pixel (bitmap memory starts with the top row).
private func topLeftPixel(_ image: CGImage) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Draw so that the image's top-left pixel lands on the single pixel
    context.draw(image, in: CGRect(x: 0, y: 1 - CGFloat(image.height), width: CGFloat(image.width), height: CGFloat(image.height)))
    return pixel
}

/// 200×100 px image of a 100×50 pt display: red top half, blue bottom half.
private func twoToneDisplayImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 50))   // CG origin is bottom-left: bottom half
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 50, width: 200, height: 50))  // top half
    return context.makeImage()!
}

struct CropTests {
    let displaySize = CGSize(width: 100, height: 50)

    @Test func cropUsesPixelsAndTopLeftOrigin() throws {
        let top = try #require(ScreenCaptureService.crop(twoToneDisplayImage(), localRect: CGRect(x: 10, y: 5, width: 20, height: 10), displayPointSize: displaySize))

        #expect(top.width == 40)
        #expect(top.height == 20)
        #expect(topLeftPixel(top) == [255, 0, 0, 255])
    }

    @Test func cropOfBottomHalfIsBlue() throws {
        let bottom = try #require(ScreenCaptureService.crop(twoToneDisplayImage(), localRect: CGRect(x: 0, y: 30, width: 10, height: 10), displayPointSize: displaySize))

        #expect(topLeftPixel(bottom) == [0, 0, 255, 255])
    }

    @Test func cropOutsideDisplayIsNil() {
        #expect(ScreenCaptureService.crop(twoToneDisplayImage(), localRect: CGRect(x: 500, y: 0, width: 10, height: 10), displayPointSize: displaySize) == nil)
    }
}

@Suite(.serialized)
struct PreviousAreaStoreTests {
    static let suiteName = "com.bufr.tests.previousArea"
    let store: PreviousAreaStore

    init() {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        store = PreviousAreaStore(defaults: defaults)
    }

    @Test func emptyByDefault() {
        #expect(store.load() == nil)
    }

    @Test func roundTrips() {
        let region = CaptureRegion(displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", localRect: CGRect(x: 10, y: 20, width: 300, height: 200))

        store.save(region)

        #expect(store.load() == region)
    }
}
