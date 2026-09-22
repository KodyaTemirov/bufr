import Foundation
import GRDB

/// Database access for OCR, usable off the main actor (the indexer runs in the background).
/// Writes touch only `ocr_text`, so they never overwrite newer edits of other columns.
struct OCRRepository: Sendable {
    struct Progress: Equatable, Sendable {
        let done: Int
        let total: Int
    }

    let database: AppDatabase

    /// The newest image that has not been recognized yet.
    func nextPending(excluding skipped: Set<UUID> = []) throws -> UUID? {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.contentType == ContentType.image)
                .filter(ClipItem.Columns.ocrText == nil)
                .filter(!skipped.contains(ClipItem.Columns.id))
                .order(ClipItem.Columns.createdAt.desc)
                .fetchOne(db)?
                .id
        }
    }

    /// The image file, the hash of its current pixels and the text stored so far.
    struct Source: Sendable {
        let imagePath: String?
        let hash: String
        let ocrText: String?
    }

    /// nil when the item is gone.
    func source(for id: UUID) throws -> Source? {
        try database.dbQueue.read { db in
            try ClipItem.fetchOne(db, key: id).map { Source(imagePath: $0.imagePath, hash: $0.hash, ocrText: $0.ocrText) }
        }
    }

    /// nil = not recognized yet (or no such item), "" = recognized, no text.
    func text(for id: UUID) throws -> String? {
        try database.dbQueue.read { db in
            try ClipItem.fetchOne(db, key: id)?.ocrText
        }
    }

    /// Stores the text only if the image still has the pixels it was recognized from; returns
    /// false when it was edited meanwhile.
    @discardableResult
    func setText(_ text: String, for id: UUID, ifHash hash: String) throws -> Bool {
        try database.dbQueue.write { db in
            try ClipItem
                .filter(key: id)
                .filter(ClipItem.Columns.hash == hash)
                .updateAll(db, ClipItem.Columns.ocrText.set(to: text)) > 0
        }
    }

    func progress() throws -> Progress {
        try database.dbQueue.read { db in
            let images = ClipItem.filter(ClipItem.Columns.contentType == ContentType.image)
            let total = try images.fetchCount(db)
            let done = try images.filter(ClipItem.Columns.ocrText != nil).fetchCount(db)
            return Progress(done: done, total: total)
        }
    }

    /// Queues every image for recognition again.
    func resetAll() throws {
        try database.dbQueue.write { db in
            _ = try ClipItem
                .filter(ClipItem.Columns.contentType == ContentType.image)
                .updateAll(db, ClipItem.Columns.ocrText.set(to: nil))
        }
    }
}
