import Foundation
import Testing
@testable import Bufr

/// Clearing or expiring the history never takes anything off a board.
@MainActor
struct HistoryCleanupTests {
    let directory: URL
    let store: ClipItemStore
    let boards: PinboardStore

    init() throws {
        directory = try TestSupport.makeTempDirectory()
        let database = try AppDatabase.makeEmpty()
        store = ClipItemStore(database: database, imageStorage: ImageStorage(baseDirectory: directory))
        boards = PinboardStore(database: database)
    }

    @Test func expiredItemOnABoardIsKept() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Date(timeIntervalSince1970: 0)
        let onBoard = try store.insert(ClipItem(contentType: .text, textContent: "board", createdAt: old, hash: "h-board"))
        let loose = try store.insert(ClipItem(contentType: .text, textContent: "loose", createdAt: old, hash: "h-loose"))
        let board = try boards.create(name: "Work")
        try boards.addClip(onBoard.id, to: board.id)

        try store.deleteOlderThan(days: 30)

        try store.fetchItems()
        #expect(store.items.map(\.id) == [onBoard.id])
        try boards.fetchClips(for: board.id)
        #expect(boards.currentBoardItems.map(\.id) == [onBoard.id])
        let removed = try store.item(id: loose.id)
        #expect(removed == nil)
    }

    @Test func clearHistoryKeepsBoardItemsAndTheirImages() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = directory.appendingPathComponent("images")
        let onBoard = try store.insert(ClipItem(contentType: .image, imagePath: "board.png", hash: "h-board"))
        let loose = try store.insert(ClipItem(contentType: .image, imagePath: "loose.png", hash: "h-loose"))
        try TestImages.png().write(to: images.appendingPathComponent("board.png"))
        try TestImages.png().write(to: images.appendingPathComponent("loose.png"))
        let board = try boards.create(name: "Work")
        try boards.addClip(onBoard.id, to: board.id)

        try await store.clearHistory()

        try store.fetchItems()
        #expect(store.items.map(\.id) == [onBoard.id])
        try boards.fetchClips(for: board.id)
        #expect(boards.currentBoardItems.map(\.id) == [onBoard.id])
        #expect(FileManager.default.fileExists(atPath: images.appendingPathComponent("board.png").path))
        #expect(!FileManager.default.fileExists(atPath: images.appendingPathComponent("loose.png").path))
        let removed = try store.item(id: loose.id)
        #expect(removed == nil)
    }

    /// Only "Delete everything" empties the database.
    @Test func deleteAllStillRemovesBoardItems() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let onBoard = try store.insert(ClipItem(contentType: .text, textContent: "board", hash: "h-board"))
        let board = try boards.create(name: "Work")
        try boards.addClip(onBoard.id, to: board.id)

        try store.deleteAll()

        try store.fetchItems()
        #expect(store.items.isEmpty)
    }
}
