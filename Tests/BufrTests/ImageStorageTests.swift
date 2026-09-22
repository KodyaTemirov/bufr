import Foundation
import Testing
@testable import Bufr

struct ImageStorageTests {
    @Test func saveImageUsesBaseDirectory() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let id = UUID()

        let filename = try await storage.saveImage(TestImages.png(), id: id)

        #expect(filename == "\(id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("images/\(filename)").path))
    }

    /// Pre-3.0 rows used one UUID for the file and another for the item.
    @Test func deleteAssetsRemovesImageAndThumbnailsForBothIds() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let fileId = UUID()
        let itemId = UUID()
        let images = dir.appendingPathComponent("images")
        let thumbnails = dir.appendingPathComponent("thumbnails")
        try TestImages.png().write(to: images.appendingPathComponent("\(fileId.uuidString).png"))
        for id in [fileId, itemId] {
            try Data([1]).write(to: thumbnails.appendingPathComponent("\(id.uuidString)_thumb.png"))
        }

        await storage.deleteAssets(imagePath: "\(fileId.uuidString).png", itemId: itemId)

        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: thumbnails.path).isEmpty)
    }

    @Test func deleteAssetsIgnoresPathTraversal() async throws {
        let dir = try TestSupport.makeTempDirectory()
        let storage = ImageStorage(baseDirectory: dir)
        let outside = dir.appendingPathComponent("keep.png")
        try Data([1]).write(to: outside)

        await storage.deleteAssets(imagePath: "../keep.png", itemId: UUID())

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func uuidFromImagePath() {
        let id = UUID()
        #expect(ImageStorage.uuid(fromImagePath: "\(id.uuidString).png") == id)
        #expect(ImageStorage.uuid(fromImagePath: "not-a-uuid.png") == nil)
    }
}
