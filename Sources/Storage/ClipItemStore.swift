import Foundation
import GRDB

@MainActor @Observable
final class ClipItemStore {
    private(set) var items: [ClipItem] = []
    private let database: AppDatabase
    private let imageStorage: ImageStorage

    init(database: AppDatabase, imageStorage: ImageStorage = .shared) {
        self.database = database
        self.imageStorage = imageStorage
    }

    // MARK: - Fetch

    func fetchItems(limit: Int = 200) throws {
        items = try database.dbQueue.read { db in
            try ClipItem
                .order(ClipItem.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchItems(origin: ClipOrigin, limit: Int = 200) throws -> [ClipItem] {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.origin == origin)
                .order(ClipItem.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchItems(contentType: ContentType, limit: Int = 200) throws -> [ClipItem] {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.contentType == contentType)
                .order(ClipItem.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Insert (with deduplication)

    func item(id: UUID) throws -> ClipItem? {
        try database.dbQueue.read { db in
            try ClipItem.fetchOne(db, key: id)
        }
    }

    func existingItem(hash: String) throws -> ClipItem? {
        try database.dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.hash == hash)
                .fetchOne(db)
        }
    }

    /// Inserts `item`. With `deduplicate`, an item with the same hash is brought to the top
    /// (its `createdAt` is bumped) and returned instead of inserting a copy.
    @discardableResult
    func insert(_ item: ClipItem, deduplicate: Bool = true) throws -> ClipItem {
        try database.dbQueue.write { db in
            if deduplicate, var existing = try ClipItem
                .filter(ClipItem.Columns.hash == item.hash)
                .fetchOne(db) {
                existing.createdAt = Date()
                try existing.update(db)
                return existing
            }

            try item.insert(db)
            return item
        }
    }

    /// Moves an existing item to the top of the history. Only `created_at` is written:
    /// callers may hold a copy that is older than the row (e.g. renamed since).
    @discardableResult
    func touch(_ item: ClipItem) throws -> ClipItem {
        let touched = try database.dbQueue.write { db -> ClipItem in
            try ClipItem
                .filter(key: item.id)
                .updateAll(db, ClipItem.Columns.createdAt.set(to: Date()))
            return try ClipItem.find(db, key: item.id)
        }
        prependItem(touched)
        return touched
    }

    // MARK: - Delete

    func delete(_ item: ClipItem) throws {
        _ = try database.dbQueue.write { db in
            try item.delete(db)
        }
    }

    func deleteAll() throws {
        _ = try database.dbQueue.write { db in
            try ClipItem.deleteAll(db)
        }
    }

    /// "Clear history": everything the history cleanup may remove, with its image files.
    func clearHistory() async throws {
        let removed = try deleteRemovable(Self.removable)
        await deleteAssets(of: removed)
    }

    func deleteOlderThan(days: Int) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let removed = try deleteRemovable(Self.removable.filter(ClipItem.Columns.createdAt < cutoffDate))
        guard !removed.isEmpty else { return }
        Task { await deleteAssets(of: removed) }
    }

    /// The history cleanup never removes pinned items or anything on a board: deleting the row
    /// would take it off its boards too (`pinboard_items` cascades).
    private static var removable: QueryInterfaceRequest<ClipItem> {
        ClipItem
            .filter(ClipItem.Columns.isPinned == false)
            .filter(sql: "id NOT IN (SELECT clip_id FROM pinboard_items)")
    }

    private func deleteRemovable(_ request: QueryInterfaceRequest<ClipItem>) throws -> [ClipItem] {
        try database.dbQueue.write { db in
            let items = try request.fetchAll(db)
            try request.deleteAll(db)
            return items
        }
    }

    private func deleteAssets(of items: [ClipItem]) async {
        for item in items where item.imagePath != nil {
            await imageStorage.deleteAssets(imagePath: item.imagePath, itemId: item.id)
        }
    }

    // MARK: - Search (FTS5)

    func search(query: String) throws -> [ClipItem] {
        try search(query: query, origin: nil)
    }

    /// Full-text search, optionally limited to one origin (e.g. the Screenshots tab).
    func search(query: String, origin: ClipOrigin?) throws -> [ClipItem] {
        guard !query.isEmpty else {
            if let origin { return try fetchItems(origin: origin) }
            return items
        }

        return try database.dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            var arguments: StatementArguments = [pattern]
            var originFilter = ""
            if let origin {
                originFilter = "WHERE clip_items.origin = ?"
                arguments += [origin]
            }
            let sql = """
                SELECT clip_items.*
                FROM clip_items
                JOIN clip_items_fts ON clip_items_fts.rowid = clip_items.rowid
                    AND clip_items_fts MATCH ?
                \(originFilter)
                ORDER BY clip_items.created_at DESC
                LIMIT 200
            """
            return try ClipItem.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    // MARK: - Update

    func toggleFavorite(_ item: ClipItem) throws {
        try updateColumns(of: item.id, [ClipItem.Columns.isFavorite.set(to: !item.isFavorite)])
    }

    func togglePinned(_ item: ClipItem) throws {
        try updateColumns(of: item.id, [ClipItem.Columns.isPinned.set(to: !item.isPinned)])
    }

    func updateTextContent(_ item: ClipItem, newText: String) throws {
        try updateColumns(of: item.id, [ClipItem.Columns.textContent.set(to: newText)])
    }

    func updateCustomTitle(_ item: ClipItem, newTitle: String?) throws {
        try updateColumns(of: item.id, [ClipItem.Columns.customTitle.set(to: (newTitle?.isEmpty == true) ? nil : newTitle)])
    }

    /// Only `saved_file_path` is written, so a stale copy can't revert other edits.
    func setSavedFilePath(_ path: String?, for id: UUID) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            try ClipItem
                .filter(key: id)
                .updateAll(db, ClipItem.Columns.savedFilePath.set(to: path))
            return try ClipItem.find(db, key: id)
        }
        updateItemInPlace(updated)
    }

    /// After editing an image: new flattened content, so hash, size and layers change; the
    /// OCR text is cleared for re-recognition and the item moves to the top. Other columns
    /// (title, favourites, …) are left alone.
    @discardableResult
    func applyEdit(id: UUID, hash: String, annotationPath: String?, pixelWidth: Int, pixelHeight: Int) throws -> ClipItem {
        let updated = try database.dbQueue.write { db -> ClipItem in
            try ClipItem
                .filter(key: id)
                .updateAll(db, [
                    ClipItem.Columns.hash.set(to: hash),
                    ClipItem.Columns.annotationPath.set(to: annotationPath),
                    ClipItem.Columns.pixelWidth.set(to: pixelWidth),
                    ClipItem.Columns.pixelHeight.set(to: pixelHeight),
                    ClipItem.Columns.ocrText.set(to: nil),
                    ClipItem.Columns.createdAt.set(to: Date()),
                ])
            return try ClipItem.find(db, key: id)
        }
        prependItem(updated)
        return updated
    }

    @discardableResult
    func clearAnnotationPath(id: UUID) throws -> ClipItem {
        let updated = try database.dbQueue.write { db -> ClipItem in
            try ClipItem.filter(key: id).updateAll(db, ClipItem.Columns.annotationPath.set(to: nil))
            return try ClipItem.find(db, key: id)
        }
        updateItemInPlace(updated)
        return updated
    }

    // MARK: - In-place update

    /// Writes only the given columns: a card's copy of the item may predate OCR or an edit,
    /// and a full-row update would write those stale values back.
    private func updateColumns(of id: UUID, _ assignments: [ColumnAssignment]) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            try ClipItem.filter(key: id).updateAll(db, assignments)
            return try ClipItem.find(db, key: id)
        }
        updateItemInPlace(updated)
    }

    private func updateItemInPlace(_ updated: ClipItem) {
        if let idx = items.firstIndex(where: { $0.id == updated.id }) {
            items[idx] = updated
        }
    }

    func prependItem(_ item: ClipItem) {
        // If duplicate (same id), remove old position first
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        // Keep within limit
        if items.count > 200 {
            items.removeLast(items.count - 200)
        }
    }
}
