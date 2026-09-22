import Foundation
import Testing
@testable import Bufr

struct DragFileResolverTests {
    let dir: URL
    let temp: URL

    init() throws {
        dir = try TestSupport.makeTempDirectory()
        temp = try TestSupport.makeTempDirectory()
    }

    @Test func prefersTheCopyInTheScreenshotsFolder() throws {
        let saved = dir.appendingPathComponent("Screenshot 1.png")
        try TestImages.png().write(to: saved)

        let url = try DragFileResolver.fileURL(savedFilePath: saved.path, internalFile: nil, suggestedName: "x.png", temporaryDirectory: temp)

        #expect(url == saved)
    }

    /// Clipboard images and pre-3.0 items have no folder copy.
    @Test func otherwiseWritesATemporaryFileWithAReadableName() throws {
        let historyFile = dir.appendingPathComponent("\(UUID().uuidString).png")
        let png = TestImages.png(width: 6, height: 2)
        try png.write(to: historyFile)

        let url = try #require(try DragFileResolver.fileURL(savedFilePath: nil, internalFile: historyFile, suggestedName: "Screenshot 2026.png", temporaryDirectory: temp))

        #expect(url.lastPathComponent == "Screenshot 2026.png")
        #expect(url.path.hasPrefix(temp.path))
        #expect(try Data(contentsOf: url) == png)
    }

    @Test func missingFolderCopyFallsBackToTemporaryFile() throws {
        let historyFile = dir.appendingPathComponent("a.png")
        try TestImages.png().write(to: historyFile)

        let url = try DragFileResolver.fileURL(savedFilePath: "/nonexistent/shot.png", internalFile: historyFile, suggestedName: "shot.png", temporaryDirectory: temp)

        #expect(url?.path.hasPrefix(temp.path) == true)
    }

    @Test func legacyTIFFBytesAreDraggedAsRealPNG() throws {
        let historyFile = dir.appendingPathComponent("legacy.png")
        try TestImages.tiff().write(to: historyFile)

        let url = try #require(try DragFileResolver.fileURL(savedFilePath: nil, internalFile: historyFile, suggestedName: "Image.png", temporaryDirectory: temp))

        #expect(Array(try Data(contentsOf: url).prefix(4)) == TestImages.pngSignature)
    }

    @Test func nothingToDragReturnsNil() throws {
        #expect(try DragFileResolver.fileURL(savedFilePath: nil, internalFile: nil, suggestedName: "x.png", temporaryDirectory: temp) == nil)
    }

    /// Dragged copies must not pile up (or outlive a deleted item) in the temp folder.
    @Test func purgeRemovesOnlyOldDragFolders() throws {
        let old = temp.appendingPathComponent("old", isDirectory: true)
        let fresh = temp.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: old.path)

        DragFileResolver.purge(temporaryDirectory: temp, olderThan: 3600, now: now)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}
