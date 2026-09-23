import AppKit
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Bufr

/// Long (scrolling) screenshots are recognized in overlapping strips: shrinking them to the
/// 6144 px limit would make every letter unreadable.
struct OCRTilingTests {
    @Test func tilesCoverATallImageWithOverlap() {
        let tiles = OCRTiling.tiles(width: 800, height: 9000)

        #expect(tiles == [
            CGRect(x: 0, y: 0, width: 800, height: 4096),
            CGRect(x: 0, y: 3896, width: 800, height: 4096),
            CGRect(x: 0, y: 7792, width: 800, height: 1208),
        ])
    }

    @Test func shortOrWideImageIsOneTile() {
        #expect(OCRTiling.tiles(width: 3000, height: 2000) == [CGRect(x: 0, y: 0, width: 3000, height: 2000)])
        #expect(OCRTiling.tiles(width: 1000, height: 6000) == [CGRect(x: 0, y: 0, width: 1000, height: 6000)])
        #expect(OCRTiling.tiles(width: 4000, height: 7000) == [CGRect(x: 0, y: 0, width: 4000, height: 7000)])
    }

    @Test func joinDropsLinesRepeatedAtTheSeam() {
        #expect(OCRTiling.join(["a\nb\nc", "b\nc\nd"]) == "a\nb\nc\nd")
        #expect(OCRTiling.join(["a", "", "b"]) == "a\nb")
    }
}

@MainActor
struct OCRTallImageTests {
    let store: ClipItemStore
    let storage: ImageStorage
    let ingestor: ClipIngestor
    let repository: OCRRepository

    init() throws {
        let database = try AppDatabase.makeEmpty()
        store = ClipItemStore(database: database)
        storage = ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        ingestor = ClipIngestor(store: store, imageStorage: storage)
        repository = OCRRepository(database: database)
    }

    private func tallImage(top: String, bottom: String, width: Int = 900, height: Int = 9000) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (text, y) in [(top, height - 150), (bottom, 100)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 56)]))
            context.textPosition = CGPoint(x: 30, y: y)
            CTLineDraw(line, context)
        }
        return context.makeImage()!
    }

    private func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func tallImageIsRecognizedInTiles() async throws {
        let heights = HeightRecorder()
        let indexer = OCRIndexer(repository: repository, imageStorage: storage, recognize: { image in
            await heights.record(image.height)
            return "strip"
        }, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 800, height: 9000)), origin: .screenshot))

        await indexer.enqueue(item.id)
        await indexer.waitUntilIdle()

        #expect(await heights.values == [4096, 4096, 1208])
        #expect(try repository.text(for: item.id) == "strip")
    }

    /// Review Focus 5: search finds words at the bottom of a long capture (real Vision).
    @Test func bottomOfATallImageIsRecognized() async throws {
        let indexer = OCRIndexer(repository: repository, imageStorage: storage, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(tallImage(top: "Top Alpha", bottom: "Bottom Omega")), origin: .screenshot))

        await indexer.enqueue(item.id)
        await indexer.waitUntilIdle()

        let text = try #require(try repository.text(for: item.id))
        #expect(text.contains("Alpha"))
        #expect(text.contains("Omega"))
    }
}

actor HeightRecorder {
    private(set) var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}
