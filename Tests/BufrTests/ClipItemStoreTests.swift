import Foundation
import Testing
@testable import Bufr

@MainActor
struct ClipItemStoreTests {
    let store: ClipItemStore

    init() throws {
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
    }

    @Test func insertDeduplicatesByHashByDefault() throws {
        let first = try store.insert(ClipItem(contentType: .text, textContent: "a", hash: "same"))
        let second = try store.insert(ClipItem(contentType: .text, textContent: "a", hash: "same"))

        #expect(second.id == first.id)
        #expect(try store.existingItem(hash: "same")?.id == first.id)
    }

    @Test func insertWithoutDeduplicationKeepsBoth() throws {
        let first = try store.insert(ClipItem(contentType: .image, hash: "shot"), deduplicate: false)
        let second = try store.insert(ClipItem(contentType: .image, hash: "shot"), deduplicate: false)

        #expect(first.id != second.id)
        try store.fetchItems()
        #expect(store.items.count == 2)
    }

    @Test func existingItemReturnsNilForUnknownHash() throws {
        #expect(try store.existingItem(hash: "missing") == nil)
    }

    @Test func touchMovesItemToTopAndBumpsDate() throws {
        let old = try store.insert(ClipItem(
            contentType: .text, textContent: "old",
            createdAt: Date(timeIntervalSince1970: 0), hash: "h-old"
        ))
        // Explicit past date: created_at is stored with millisecond precision, so an insert and
        // a touch within the same millisecond would tie
        let new = try store.insert(ClipItem(
            contentType: .text, textContent: "new",
            createdAt: Date(timeIntervalSince1970: 1_000), hash: "h-new"
        ))
        try store.fetchItems()
        #expect(store.items.map(\.id) == [new.id, old.id])

        let touched = try store.touch(old)

        #expect(touched.createdAt > Date(timeIntervalSince1970: 0))
        #expect(store.items.map(\.id) == [old.id, new.id])
        try store.fetchItems()
        #expect(store.items.first?.id == old.id)
    }

    /// Pinboard cards and the menu bar list hold copies that can be older than the database row.
    @Test func touchWithStaleCopyKeepsNewerEdits() throws {
        let stale = try store.insert(ClipItem(contentType: .text, textContent: "text", hash: "h-stale"))
        try store.updateCustomTitle(stale, newTitle: "Renamed")

        let touched = try store.touch(stale)

        #expect(touched.customTitle == "Renamed")
        #expect(try store.existingItem(hash: "h-stale")?.customTitle == "Renamed")
    }

    @Test func fetchItemsFiltersByOrigin() throws {
        try store.insert(ClipItem(contentType: .text, textContent: "copied", hash: "h1", origin: .clipboard))
        let shot = try store.insert(ClipItem(contentType: .image, imagePath: "s.png", hash: "h2", origin: .screenshot))
        try store.insert(ClipItem(contentType: .text, textContent: "legacy", hash: "h3"))

        #expect(try store.fetchItems(origin: .screenshot).map(\.id) == [shot.id])
    }

    @Test func searchWithinOrigin() throws {
        try store.insert(ClipItem(contentType: .text, textContent: "invoice text", hash: "h1", origin: .clipboard))
        let shot = try store.insert(ClipItem(
            contentType: .image, imagePath: "s.png", hash: "h2",
            origin: .screenshot, ocrText: "invoice screenshot"
        ))

        #expect(try store.search(query: "invoice", origin: .screenshot).map(\.id) == [shot.id])
        #expect(try store.search(query: "invoice", origin: nil).count == 2)
    }

    @Test func setSavedFilePathKeepsOtherFields() throws {
        let item = try store.insert(ClipItem(contentType: .image, imagePath: "s.png", hash: "h", origin: .screenshot))
        try store.updateCustomTitle(item, newTitle: "Chart")

        try store.setSavedFilePath("/tmp/shot.png", for: item.id)

        let loaded = try #require(try store.existingItem(hash: "h"))
        #expect(loaded.savedFilePath == "/tmp/shot.png")
        #expect(loaded.customTitle == "Chart")
    }

    @Test func pixelSizeTextAndScreenshotFlag() {
        let shot = ClipItem(contentType: .image, hash: "h", origin: .screenshot, pixelWidth: 2880, pixelHeight: 1800)

        #expect(shot.isScreenshot)
        #expect(shot.pixelSizeText == "2880 × 1800")
        #expect(ClipItem(contentType: .image, hash: "h2").pixelSizeText == nil)
    }

    /// A card's in-memory copy may predate OCR or an edit; renaming or starring it must not
    /// write those stale fields back.
    @Test func renameAndFavoriteWithStaleCopyKeepNewerColumns() throws {
        let database = try AppDatabase.makeEmpty()
        let store = ClipItemStore(database: database)
        let stale = try store.insert(ClipItem(contentType: .image, imagePath: "s.png", hash: "old", origin: .screenshot))
        _ = try store.applyEdit(id: stale.id, hash: "new", annotationPath: "s.annotations.json", pixelWidth: 10, pixelHeight: 10)
        try OCRRepository(database: database).setText("recognized", for: stale.id, ifHash: "new")

        try store.updateCustomTitle(stale, newTitle: "Chart")
        try store.toggleFavorite(stale)
        try store.togglePinned(stale)

        let current = try #require(try store.existingItem(hash: "new"))
        #expect(current.customTitle == "Chart")
        #expect(current.isFavorite)
        #expect(current.isPinned)
        #expect(current.ocrText == "recognized")
        #expect(current.annotationPath == "s.annotations.json")
    }
}
