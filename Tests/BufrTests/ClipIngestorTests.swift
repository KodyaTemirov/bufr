import Foundation
import Testing
@testable import Bufr

@MainActor
struct ClipIngestorTests {
    let dir: URL
    let store: ClipItemStore
    let ingestor: ClipIngestor

    init() throws {
        dir = try TestSupport.makeTempDirectory()
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
        ingestor = ClipIngestor(store: store, imageStorage: ImageStorage(baseDirectory: dir))
    }

    private func imageFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("images").path).sorted()
    }

    @Test func imageFileIsNamedAfterItemId() async throws {
        let item = try await ingestor.ingestImage(.init(data: TestImages.png(), origin: .clipboard))

        #expect(item.imagePath == "\(item.id.uuidString).png")
        #expect(try imageFiles() == ["\(item.id.uuidString).png"])
        #expect(item.origin == .clipboard)
        #expect(item.pixelWidth == 4)
        #expect(item.pixelHeight == 3)
        #expect(store.items.first?.id == item.id)
    }

    @Test func duplicateImageWritesNoSecondFile() async throws {
        let data = TestImages.png(width: 9, height: 9)
        let first = try await ingestor.ingestImage(.init(data: data, origin: .clipboard))
        let second = try await ingestor.ingestImage(.init(data: data, origin: .clipboard))

        #expect(second.id == first.id)
        #expect(try imageFiles().count == 1)
        #expect(store.items.count == 1)
    }

    @Test func concurrentDuplicatesLeaveOneItemAndOneFile() async throws {
        let data = TestImages.png(width: 7, height: 5)
        async let a = ingestor.ingestImage(.init(data: data, origin: .clipboard))
        async let b = ingestor.ingestImage(.init(data: data, origin: .clipboard))
        let (first, second) = try await (a, b)

        #expect(first.id == second.id)
        #expect(try imageFiles() == ["\(first.id.uuidString).png"])
        #expect(store.items.count == 1)
    }

    @Test func screenshotsSkipDeduplication() async throws {
        let data = TestImages.png(width: 8, height: 8)
        let first = try await ingestor.ingestImage(.init(data: data, origin: .screenshot, deduplicate: false))
        let second = try await ingestor.ingestImage(.init(data: data, origin: .screenshot, deduplicate: false))

        #expect(first.id != second.id)
        #expect(try imageFiles().count == 2)
    }

    @Test func tiffIsStoredAsRealPNGButHashedByOriginalBytes() async throws {
        let tiff = TestImages.tiff()
        let item = try await ingestor.ingestImage(.init(data: tiff, origin: .clipboard))

        let imagePath = try #require(item.imagePath)
        let stored = try Data(contentsOf: dir.appendingPathComponent("images/\(imagePath)"))
        #expect(Array(stored.prefix(4)) == TestImages.pngSignature)
        // Re-copying the same TIFF from another app must still deduplicate
        #expect(item.hash == HashGenerator.sha256(tiff))
    }

    @Test func unreadableImageThrowsAndWritesNothing() async throws {
        await #expect(throws: ClipIngestor.IngestError.self) {
            try await ingestor.ingestImage(.init(data: Data([0, 1, 2]), origin: .clipboard))
        }
        #expect(try imageFiles().isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test func contentIsDeduplicatedAndPrepended() throws {
        let input = ClipIngestor.ContentInput(contentType: .text, textContent: "hello", origin: .clipboard)
        let first = try ingestor.ingestContent(input)
        let second = try ingestor.ingestContent(input)

        #expect(first.id == second.id)
        #expect(store.items.map(\.id) == [first.id])
        #expect(first.origin == .clipboard)
    }

    @Test func newImagesAreReportedForTextRecognition() async throws {
        var reported: [UUID] = []
        ingestor.onImageIngested = { reported.append($0) }

        let first = try await ingestor.ingestImage(.init(data: TestImages.png(width: 11, height: 3), origin: .clipboard))
        _ = try await ingestor.ingestImage(.init(data: TestImages.png(width: 11, height: 3), origin: .clipboard)) // duplicate

        #expect(reported == [first.id])
    }
}
