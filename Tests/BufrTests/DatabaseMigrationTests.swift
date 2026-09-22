import Foundation
import GRDB
import Testing
@testable import Bufr

@MainActor
struct DatabaseMigrationTests {
    @Test func v4KeepsLegacyRowsSearchable() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3_pinboardItemsIndexes")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO clip_items (id, content_type, text_content, created_at, is_pinned, is_favorite, hash)
                VALUES ('11111111-1111-1111-1111-111111111111', 'text', 'legacy hello',
                        '2026-01-01 00:00:00.000', 0, 0, 'h-legacy')
                """)
        }

        let database = try AppDatabase(dbQueue: queue) // applies v4
        let store = ClipItemStore(database: database)

        let found = try store.search(query: "legacy")
        #expect(found.count == 1)
        #expect(found.first?.origin == nil)
        #expect(found.first?.ocrText == nil)
    }

    @Test func ocrTextIsFullTextSearchable() throws {
        let store = ClipItemStore(database: try AppDatabase.makeEmpty())
        try store.insert(ClipItem(
            contentType: .image, imagePath: "a.png", hash: "h-ocr",
            origin: .screenshot, ocrText: "Привет мир"
        ))

        #expect(try store.search(query: "прив").count == 1)
    }

    @Test func newFieldsRoundTripThroughDatabase() throws {
        let database = try AppDatabase.makeEmpty()
        // Fixed date: SQLite stores milliseconds, Date() has sub-millisecond precision
        let item = ClipItem(
            contentType: .image, imagePath: "b.png",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), hash: "h-fields",
            origin: .screenshot, ocrText: "", annotationPath: "b.annotations.json",
            savedFilePath: "/Users/me/Pictures/Bufr/shot.png", pixelWidth: 2880, pixelHeight: 1800
        )
        try database.dbQueue.write { db in try item.insert(db) }

        let loaded = try database.dbQueue.read { db in
            try ClipItem.filter(ClipItem.Columns.hash == "h-fields").fetchOne(db)
        }
        #expect(loaded == item)
    }
}
