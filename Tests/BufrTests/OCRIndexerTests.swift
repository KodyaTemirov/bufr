import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Bufr

@MainActor
struct OCRIndexerTests {
    let database: AppDatabase
    let store: ClipItemStore
    let storage: ImageStorage
    let ingestor: ClipIngestor
    let repository: OCRRepository
    let indexer: OCRIndexer

    init() throws {
        database = try AppDatabase.makeEmpty()
        store = ClipItemStore(database: database)
        storage = ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        ingestor = ClipIngestor(store: store, imageStorage: storage)
        repository = OCRRepository(database: database)
        indexer = OCRIndexer(repository: repository, imageStorage: storage, pauseBetweenImages: .zero)
    }

    private func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func backfillRecognizesTextInExistingImages() async throws {
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.text("Invoice 4521")), origin: .clipboard))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id)?.contains("Invoice") == true)
        #expect(try store.search(query: "invoice").map(\.id) == [item.id])
    }

    @Test func imageWithoutTextIsMarkedDone() async throws {
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.blank()), origin: .screenshot))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == "")
        #expect(try repository.nextPending() == nil)
    }

    /// The history file can vanish (deleted card, cleaned folder) while the item is queued.
    @Test func missingFileIsSkipped() async throws {
        let item = try store.insert(ClipItem(contentType: .image, imagePath: "missing.png", hash: "gone"))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == "")
    }

    @Test func disabledIndexerLeavesImagesPending() async throws {
        let item = try store.insert(ClipItem(contentType: .image, imagePath: "missing.png", hash: "off"))

        await indexer.setEnabled(false)
        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == nil)
        #expect(try repository.progress() == OCRRepository.Progress(done: 0, total: 1))
    }
}
