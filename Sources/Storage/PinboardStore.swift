import Foundation
import GRDB

@MainActor @Observable
final class PinboardStore {
    private(set) var pinboards: [Pinboard] = []
    private(set) var currentBoardItems: [ClipItem] = []
    private(set) var itemAssignmentVersion: Int = 0
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Pinboards CRUD

    func fetchPinboards() throws {
        pinboards = try database.dbQueue.read { db in
            try Pinboard
                .order(Column("sort_order").asc, Column("created_at").desc)
                .fetchAll(db)
        }
    }

    @discardableResult
    func create(name: String, icon: String? = nil, color: String? = nil) throws -> Pinboard {
        let maxOrder = pinboards.map(\.sortOrder).max() ?? 0
        let pinboard = Pinboard(
            name: name,
            icon: icon,
            color: color,
            sortOrder: maxOrder + 1
        )
        try database.dbQueue.write { db in
            try pinboard.insert(db)
        }
        try fetchPinboards()
        return pinboard
    }

    func update(_ pinboard: Pinboard) throws {
        try database.dbQueue.write { db in
            try pinboard.update(db)
        }
        try fetchPinboards()
    }

    func delete(_ pinboard: Pinboard) throws {
        _ = try database.dbQueue.write { db in
            try pinboard.delete(db)
        }
        try fetchPinboards()
    }

    // MARK: - Board Items

    func fetchClips(for pinboardId: UUID) throws {
        currentBoardItems = try database.dbQueue.read { db in
            let sql = """
                SELECT clip_items.*
                FROM clip_items
                JOIN pinboard_items ON pinboard_items.clip_id = clip_items.id
                WHERE pinboard_items.pinboard_id = ?
                ORDER BY pinboard_items.sort_order ASC, pinboard_items.added_at DESC
            """
            return try ClipItem.fetchAll(db, sql: sql, arguments: [pinboardId])
        }
    }

    func addClip(_ clipId: UUID, to pinboardId: UUID) throws {
        try database.dbQueue.write { db in
            // Check if already added
            let exists = try PinboardItem
                .filter(Column("pinboard_id") == pinboardId && Column("clip_id") == clipId)
                .fetchCount(db) > 0

            guard !exists else { return }

            let maxOrder = try PinboardItem
                .filter(Column("pinboard_id") == pinboardId)
                .select(max(Column("sort_order")))
                .asRequest(of: Int?.self)
                .fetchOne(db) ?? 0

            let item = PinboardItem(
                pinboardId: pinboardId,
                clipId: clipId,
                sortOrder: (maxOrder ?? 0) + 1
            )
            try item.insert(db)
        }
        itemAssignmentVersion += 1
    }

    func removeClip(_ clipId: UUID, from pinboardId: UUID) throws {
        _ = try database.dbQueue.write { db in
            try PinboardItem
                .filter(Column("pinboard_id") == pinboardId && Column("clip_id") == clipId)
                .deleteAll(db)
        }
        itemAssignmentVersion += 1
    }

    /// Check which pinboards contain a specific clip
    func pinboardsContaining(clipId: UUID) throws -> Set<UUID> {
        let items = try database.dbQueue.read { db in
            try PinboardItem
                .filter(Column("clip_id") == clipId)
                .fetchAll(db)
        }
        return Set(items.map(\.pinboardId))
    }
}
