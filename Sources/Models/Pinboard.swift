import Foundation
import GRDB

struct Pinboard: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinboards"

    var id: UUID
    var name: String
    var icon: String?
    var color: String?
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct PinboardItem: Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinboard_items"

    var pinboardId: UUID
    var clipId: UUID
    var sortOrder: Int
    var addedAt: Date

    init(
        pinboardId: UUID,
        clipId: UUID,
        sortOrder: Int = 0,
        addedAt: Date = Date()
    ) {
        self.pinboardId = pinboardId
        self.clipId = clipId
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case pinboardId = "pinboard_id"
        case clipId = "clip_id"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }
}
