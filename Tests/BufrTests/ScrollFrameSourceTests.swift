import CoreGraphics
import CoreVideo
import Testing
@testable import Bufr

struct ScrollFrameSourceTests {
    /// Stream frames are copied out: holding the stream's own buffers would stall its pool.
    @Test func pixelBufferBecomesAnOwnedImage() throws {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 2, kCVPixelFormatType_32BGRA, nil, &created)
        let buffer = try #require(created)

        func fill(_ blue: UInt8, _ green: UInt8, _ red: UInt8) {
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<2 {
                for x in 0..<4 {
                    let p = y * bytesPerRow + x * 4
                    // Top row: the given colour; bottom row: white
                    base[p] = y == 0 ? blue : 255
                    base[p + 1] = y == 0 ? green : 255
                    base[p + 2] = y == 0 ? red : 255
                    base[p + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }

        fill(0, 0, 255) // red
        let image = try #require(FrameConversion.image(from: buffer))
        fill(255, 0, 0) // the stream reuses its buffer for the next frame

        let top = TestImages.pixel(image, 1, 0)
        let bottom = TestImages.pixel(image, 1, 1)
        #expect(image.width == 4 && image.height == 2)
        #expect(top[0] > 250 && top[1] < 5 && top[2] < 5)
        #expect(bottom[0] > 250 && bottom[1] > 250 && bottom[2] > 250)
    }
}
