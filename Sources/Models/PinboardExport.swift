import Foundation

struct PinboardExport: Codable {
    let version: Int
    let exportDate: Date
    let pinboard: Pinboard
    let items: [ExportedClipItem]

    enum CodingKeys: String, CodingKey {
        case version
        case exportDate = "export_date"
        case pinboard
        case items
    }
}

struct BulkPinboardExport: Codable {
    let version: Int
    let exportDate: Date
    let pinboards: [PinboardExport]

    enum CodingKeys: String, CodingKey {
        case version
        case exportDate = "export_date"
        case pinboards
    }
}

struct ExportedClipItem: Codable {
    let clipItem: ClipItem
    let sortOrder: Int
    let addedAt: Date

    /// Machine-local paths (screenshots folder, editor layers) never leave this Mac.
    init(clipItem: ClipItem, sortOrder: Int, addedAt: Date) {
        self.clipItem = clipItem.withoutLocalPaths()
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case clipItem = "clip_item"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }
}
