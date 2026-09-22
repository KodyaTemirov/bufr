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
    func nextPending() throws -> UUID? {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.contentType == ContentType.image)
                .filter(ClipItem.Columns.ocrText == nil)
                .order(ClipItem.Columns.createdAt.desc)
                .fetchOne(db)?
                .id
        }
    }

    /// nil when the item is gone; `.some(nil)` when it has no image file name.
    func imagePath(for id: UUID) throws -> String?? {
        try database.dbQueue.read { db in
            try ClipItem.fetchOne(db, key: id).map { $0.imagePath }
        }
    }

    /// nil = not recognized yet (or no such item), "" = recognized, no text.
    func text(for id: UUID) throws -> String? {
        try database.dbQueue.read { db in
            try ClipItem.fetchOne(db, key: id)?.ocrText
        }
    }

    func setText(_ text: String, for id: UUID) throws {
        try database.dbQueue.write { db in
            _ = try ClipItem
                .filter(key: id)
                .updateAll(db, ClipItem.Columns.ocrText.set(to: text))
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
