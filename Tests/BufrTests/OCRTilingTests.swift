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
            CGRect(x: 0, y: 0, width: 800, height: 2048),
            CGRect(x: 0, y: 1848, width: 800, height: 2048),
            CGRect(x: 0, y: 3696, width: 800, height: 2048),
            CGRect(x: 0, y: 5544, width: 800, height: 2048),
            CGRect(x: 0, y: 7392, width: 800, height: 1608),
        ])
    }

    /// Review #6: Vision loses lines on images taller than ~2000 px (1.5–3 screens).
    @Test func twoScreensAreAlreadySplit() {
        #expect(OCRTiling.tiles(width: 1400, height: 3000).count == 2)
    }

    @Test func ordinaryScreenshotsAreOneTile() {
        #expect(OCRTiling.tiles(width: 3000, height: 2000) == [CGRect(x: 0, y: 0, width: 3000, height: 2000)])
        #expect(OCRTiling.tiles(width: 5120, height: 2880) == [CGRect(x: 0, y: 0, width: 5120, height: 2880)])
        #expect(OCRTiling.tiles(width: 1000, height: 2000) == [CGRect(x: 0, y: 0, width: 1000, height: 2000)])
    }

    /// Review #7: a line in the overlap of two strips is read twice; it is kept from one.
    @Test func seamLinesAreKeptOnce() {
        // Image 1000 px tall, strips 0…600 and 400…1000: the overlap 400…600 splits at 500
        let strips: [(rect: CGRect, lines: [OCRTextAssembler.Line])] = [
            (CGRect(x: 0, y: 0, width: 800, height: 600), [
                line("top", pixelTop: 50, stripTop: 0, stripHeight: 600),
                line("seam", pixelTop: 470, stripTop: 0, stripHeight: 600), // centre 485: first strip
                line("lower sea", pixelTop: 560, stripTop: 0, stripHeight: 600), // cut at the edge
            ]),
            (CGRect(x: 0, y: 400, width: 800, height: 600), [
                line("seam", pixelTop: 470, stripTop: 400, stripHeight: 600),
                line("lower seam", pixelTop: 560, stripTop: 400, stripHeight: 600), // centre 590: second strip
                line("bottom", pixelTop: 900, stripTop: 400, stripHeight: 600),
            ]),
        ]

        #expect(OCRTiling.assemble(strips, imageHeight: 1000) == "top\n\nseam\n\nlower seam\n\nbottom")
    }

    /// A 30 px line at `pixelTop` of the whole image, as Vision reports it for its strip.
    private func line(_ text: String, pixelTop: CGFloat, stripTop: CGFloat, stripHeight: CGFloat) -> OCRTextAssembler.Line {
        let top = (pixelTop - stripTop) / stripHeight
        let height = 30 / stripHeight
        return OCRTextAssembler.Line(text: text, box: CGRect(x: 0.05, y: 1 - top - height, width: 0.5, height: height))
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
            return [OCRTextAssembler.Line(text: "strip", box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.01))]
        }, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 800, height: 9000)), origin: .screenshot))

        await indexer.enqueue(item.id)
        await indexer.waitUntilIdle()

        #expect(await heights.values == [2048, 2048, 2048, 2048, 1608])
        #expect(try repository.text(for: item.id)?.hasPrefix("strip") == true)
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

extension OCRTallImageTests {
    /// Reviews #6 and #7 with real Vision: 26 px text on a long capture — every line found,
    /// none twice.
    @Test func everyLineOfALongCaptureIsFoundOnce() async throws {
        let width = 900, height = 4200
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let count = (height - 60) / 40
        for index in 0..<count {
            let text = String(format: "Entry %03d reading notes", index + 1)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 26)]))
            context.textPosition = CGPoint(x: 30, y: height - 40 - index * 40)
            CTLineDraw(line, context)
        }
        let indexer = OCRIndexer(repository: repository, imageStorage: storage, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(context.makeImage()!), origin: .screenshot))

        await indexer.enqueue(item.id)
        await indexer.waitUntilIdle()

        let text = try #require(try repository.text(for: item.id))
        var found = 0
        var repeated: [String] = []
        for index in 0..<count {
            let label = String(format: "Entry %03d", index + 1)
            let occurrences = text.components(separatedBy: label).count - 1
            if occurrences >= 1 { found += 1 }
            if occurrences > 1 { repeated.append(label) }
        }
        #expect(Double(found) >= Double(count) * 0.95, "found \(found) of \(count)")
        #expect(repeated.isEmpty, "\(repeated)")
    }
}

actor HeightRecorder {
    private(set) var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}