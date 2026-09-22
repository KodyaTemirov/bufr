import Foundation
import Testing
@testable import Bufr

struct ImageEncoderTests {
    @Test func pngPassesThroughUnchanged() throws {
        let png = TestImages.png(width: 5, height: 2)
        let result = try #require(ImageEncoder.normalizedPNG(png))

        #expect(result.pngData == png)
        #expect(result.pixelWidth == 5)
        #expect(result.pixelHeight == 2)
    }

    @Test func tiffIsConvertedToPNG() throws {
        let result = try #require(ImageEncoder.normalizedPNG(TestImages.tiff(width: 6, height: 4)))

        #expect(Array(result.pngData.prefix(4)) == TestImages.pngSignature)
        #expect(result.pixelWidth == 6)
        #expect(result.pixelHeight == 4)
    }

    @Test func garbageReturnsNil() {
        #expect(ImageEncoder.normalizedPNG(Data([0, 1, 2, 3])) == nil)
    }
}
