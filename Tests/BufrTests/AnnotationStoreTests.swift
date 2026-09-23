import CoreGraphics
import Foundation
import Testing
@testable import Bufr

@MainActor
struct AnnotationStoreTests {
    let imagesDir: URL
    let savedFolder: URL
    let clipStore: ClipItemStore
    let storage: ImageStorage
    let ingestor: ClipIngestor
    let annotations: AnnotationStore

    init() throws {
        let base = try TestSupport.makeTempDirectory()
        imagesDir = base.appendingPathComponent("images")
        savedFolder = try TestSupport.makeTempDirectory()
        clipStore = ClipItemStore(database: try AppDatabase.makeEmpty())
        storage = ImageStorage(baseDirectory: base)
        ingestor = ClipIngestor(store: clipStore, imageStorage: storage)
        annotations = AnnotationStore(store: clipStore, imageStorage: storage)
    }

    private func isRed(_ rgba: [UInt8]) -> Bool { rgba[0] > 200 && rgba[1] < 90 && rgba[2] < 90 }
    private func isWhite(_ rgba: [UInt8]) -> Bool { rgba[0] > 245 && rgba[1] > 245 && rgba[2] > 245 }

    /// A white 100×60 px Retina screenshot with a copy in the screenshots folder.
    private func makeScreenshot() async throws -> ClipItem {
        let png = try #require(ImageEncoder.pngData(from: TestImages.blank(width: 100, height: 60), pointScale: 2, downscaleToOneX: false))
        let item = try await ingestor.ingestImage(.init(data: png, origin: .screenshot, deduplicate: false))
        let saved = savedFolder.appendingPathComponent("Shot.png")
        try png.write(to: saved)
        try clipStore.setSavedFilePath(saved.path, for: item.id)
        return try #require(try clipStore.existingItem(hash: item.hash))
    }

    private func redSquare() -> Annotation {
        Annotation(shape: .filledRectangle(CGRect(x: 0, y: 0, width: 20, height: 20)), style: AnnotationStyle(color: .red, lineWidth: 8, fontSize: 48))
    }

    private func image(at url: URL) throws -> CGImage {
        let data = try Data(contentsOf: url)
        return try #require(TestImages.decode(data))
    }

    private func fileId(_ item: ClipItem) throws -> String {
        let imagePath = try #require(item.imagePath)
        return try #require(ImageStorage.uuid(fromImagePath: imagePath)).uuidString
    }

    private func savedImage(_ item: ClipItem) throws -> CGImage {
        let path = try #require(item.savedFilePath)
        return try image(at: URL(fileURLWithPath: path))
    }

    @Test func newSessionStartsFromTheImageWithItsPointScale() async throws {
        let item = try await makeScreenshot()

        let session = try await annotations.open(item)

        #expect(session.document.annotations.isEmpty)
        #expect(session.document.pointScale == 2)
        #expect(session.base.width == 100)
    }

    @Test func commitFlattensAndKeepsTheOriginal() async throws {
        let item = try await makeScreenshot()
        var session = try await annotations.open(item)
        session.document.add(redSquare())

        let edited = try await annotations.commit(session.document, base: session.base, for: item)

        let id = try fileId(item)
        #expect(edited.annotationPath == "\(id).annotations.json")
        #expect(edited.hash != item.hash)
        #expect(edited.ocrText == nil)
        #expect(FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("\(id)_orig.png").path))
        let flattened = try image(at: imagesDir.appendingPathComponent("\(id).png"))
        let saved = try savedImage(item)
        #expect(isRed(TestImages.pixel(flattened, 5, 5)))
        #expect(isRed(TestImages.pixel(saved, 5, 5)))
    }

    @Test func reopenReturnsLayersOverOriginal() async throws {
        let item = try await makeScreenshot()
        var session = try await annotations.open(item)
        session.document.add(redSquare())
        let edited = try await annotations.commit(session.document, base: session.base, for: item)

        let reopened = try await annotations.open(edited)

        #expect(reopened.document.annotations == session.document.annotations)
        #expect(isWhite(TestImages.pixel(reopened.base, 5, 5)))
    }

    @Test func revertRestoresOriginal() async throws {
        let item = try await makeScreenshot()
        let id = try fileId(item)
        var session = try await annotations.open(item)
        session.document.add(redSquare())
        let edited = try await annotations.commit(session.document, base: session.base, for: item)

        let reverted = try await annotations.revert(edited)

        #expect(reverted.annotationPath == nil)
        #expect(reverted.hash == item.hash)
        let restored = try image(at: imagesDir.appendingPathComponent("\(id).png"))
        let saved = try savedImage(item)
        #expect(isWhite(TestImages.pixel(restored, 5, 5)))
        #expect(isWhite(TestImages.pixel(saved, 5, 5)))
        #expect(!FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("\(id)_orig.png").path))
        #expect(!FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("\(id).annotations.json").path))
    }

    /// For privacy after pixelating: the original under the pixels is deleted.
    @Test func flattenDropsLayersAndKeepsTheResult() async throws {
        let item = try await makeScreenshot()
        let id = try fileId(item)
        var session = try await annotations.open(item)
        session.document.add(redSquare())
        let edited = try await annotations.commit(session.document, base: session.base, for: item)

        let flattened = try await annotations.flatten(edited)

        #expect(flattened.annotationPath == nil)
        let result = try image(at: imagesDir.appendingPathComponent("\(id).png"))
        #expect(isRed(TestImages.pixel(result, 5, 5)))
        #expect(!FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("\(id)_orig.png").path))
    }

    /// "Remove Layers" or "Revert" from the card while the editor is still open: a later save
    /// from that editor must not bake the flattened image in as the new original.
    @Test func saveFromAnOutdatedEditorIsRefused() async throws {
        let item = try await makeScreenshot()
        let id = try fileId(item)
        var session = try await annotations.open(item)
        session.document.add(redSquare())
        let editorItem = try await annotations.commit(session.document, base: session.base, for: item)
        _ = try await annotations.flatten(editorItem)

        await #expect(throws: AnnotationStore.StoreError.changedElsewhere) {
            try await annotations.commit(session.document, base: session.base, for: editorItem)
        }
        #expect(!FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("\(id)_orig.png").path))
    }

    @Test func deletingTheItemRemovesEditorFiles() async throws {
        let item = try await makeScreenshot()
        let id = try fileId(item)
        var session = try await annotations.open(item)
        session.document.add(redSquare())
        _ = try await annotations.commit(session.document, base: session.base, for: item)

        await storage.deleteAssets(imagePath: item.imagePath, itemId: item.id)

        #expect(try FileManager.default.contentsOfDirectory(atPath: imagesDir.path).filter { $0.hasPrefix(id) }.isEmpty)
    }
}
