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
}
