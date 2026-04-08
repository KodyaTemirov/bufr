import Foundation
import GRDB

@MainActor @Observable
final class ClipItemStore {
    private(set) var items: [ClipItem] = []
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
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

    @discardableResult
    func insert(_ item: ClipItem) throws -> ClipItem {
        try database.dbQueue.write { db in
            // Check for duplicate by hash
            if var existing = try ClipItem
                .filter(ClipItem.Columns.hash == item.hash)
                .fetchOne(db) {
                // Update timestamp to bring it to top
                existing.createdAt = Date()
                try existing.update(db)
                return existing
            }

            let newItem = item
            try newItem.insert(db)
            return newItem
        }
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

    func deleteOlderThan(days: Int) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let imageRefs = try database.dbQueue.write { db -> [(String, UUID)] in
            let itemsToDelete = try ClipItem
                .filter(ClipItem.Columns.createdAt < cutoffDate)
                .filter(ClipItem.Columns.isPinned == false)
                .fetchAll(db)

            let refs = itemsToDelete.compactMap { item -> (String, UUID)? in
                guard let path = item.imagePath else { return nil }
                return (path, item.id)
            }

            try ClipItem
                .filter(ClipItem.Columns.createdAt < cutoffDate)
                .filter(ClipItem.Columns.isPinned == false)
                .deleteAll(db)

            return refs
        }

        if !imageRefs.isEmpty {
            Task {
                for (path, id) in imageRefs {
                    await ImageStorage.shared.deleteImage(filename: path, id: id)
                }
            }
        }
    }

    func enforceHistoryLimit(_ limit: Int) throws {
        let imageRefs = try database.dbQueue.write { db -> [(String, UUID)] in
            let count = try ClipItem.fetchCount(db)
            guard count > limit else { return [] }
            let excess = count - limit
            let oldItems = try ClipItem
                .filter(ClipItem.Columns.isPinned == false)
                .order(ClipItem.Columns.createdAt.asc)
                .limit(excess)
                .fetchAll(db)

            let refs = oldItems.compactMap { item -> (String, UUID)? in
                guard let path = item.imagePath else { return nil }
                return (path, item.id)
            }

            for item in oldItems {
                try item.delete(db)
            }

            return refs
        }

        if !imageRefs.isEmpty {
            Task {
                for (path, id) in imageRefs {
                    await ImageStorage.shared.deleteImage(filename: path, id: id)
                }
            }
        }
    }

    // MARK: - Search (FTS5)

    func search(query: String) throws -> [ClipItem] {
        guard !query.isEmpty else { return items }

        return try database.dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            let sql = """
                SELECT clip_items.*
                FROM clip_items
                JOIN clip_items_fts ON clip_items_fts.rowid = clip_items.rowid
                    AND clip_items_fts MATCH ?
                ORDER BY clip_items.created_at DESC
                LIMIT 200
            """
            return try ClipItem.fetchAll(db, sql: sql, arguments: [pattern])
        }
    }

    // MARK: - Update

    func toggleFavorite(_ item: ClipItem) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            var u = item
            u.isFavorite.toggle()
            try u.update(db)
            return u
        }
        updateItemInPlace(updated)
    }

    func togglePinned(_ item: ClipItem) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            var u = item
            u.isPinned.toggle()
            try u.update(db)
            return u
        }
        updateItemInPlace(updated)
    }

    func updateTextContent(_ item: ClipItem, newText: String) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            var u = item
            u.textContent = newText
            try u.update(db)
            return u
        }
        updateItemInPlace(updated)
    }

    func updateCustomTitle(_ item: ClipItem, newTitle: String?) throws {
        let updated = try database.dbQueue.write { db -> ClipItem in
            var u = item
            u.customTitle = (newTitle?.isEmpty == true) ? nil : newTitle
            try u.update(db)
            return u
        }
        updateItemInPlace(updated)
    }

    // MARK: - In-place update

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
