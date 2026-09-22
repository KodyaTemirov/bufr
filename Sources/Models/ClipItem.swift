import Foundation
import GRDB

struct ClipItem: Identifiable, Equatable {
    var id: UUID
    var contentType: ContentType
    var textContent: String?
    var richContent: Data?
    var imagePath: String?
    var filePaths: String?
    var sourceAppId: String?
    var sourceAppName: String?
    var createdAt: Date
    var isPinned: Bool
    var isFavorite: Bool
    var hash: String
    var customTitle: String?
    var origin: ClipOrigin?
    var ocrText: String?          // nil = not recognized yet, "" = recognized, no text
    var annotationPath: String?   // "<uuid>.annotations.json" (editor layers)
    var savedFilePath: String?    // absolute path of the copy in the user's screenshot folder
    var pixelWidth: Int?
    var pixelHeight: Int?

    init(
        id: UUID = UUID(),
        contentType: ContentType,
        textContent: String? = nil,
        richContent: Data? = nil,
        imagePath: String? = nil,
        filePaths: String? = nil,
        sourceAppId: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isFavorite: Bool = false,
        hash: String,
        customTitle: String? = nil,
        origin: ClipOrigin? = nil,
        ocrText: String? = nil,
        annotationPath: String? = nil,
        savedFilePath: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.richContent = richContent
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.sourceAppId = sourceAppId
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.hash = hash
        self.customTitle = customTitle
        self.origin = origin
        self.ocrText = ocrText
        self.annotationPath = annotationPath
        self.savedFilePath = savedFilePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var filePathsArray: [String] {
        guard let data = filePaths?.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths
    }

    static func encodeFilePaths(_ paths: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(paths) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var displayText: String {
        let text = textContent ?? ""
        if text.count > 80 {
            return String(text.prefix(80)) + "..."
        }
        return text
    }

    var displayTitle: String {
        if let title = customTitle, !title.isEmpty {
            return title
        }
        if isScreenshot {
            return L10n("contentType.screenshot")
        }
        return contentType.displayName
    }

    var isScreenshot: Bool { origin == .screenshot }

    /// "2880 × 1800" for images whose size is known
    var pixelSizeText: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    /// Copy suitable for another machine: drops paths that only make sense locally.
    func withoutLocalPaths() -> ClipItem {
        var copy = self
        copy.annotationPath = nil
        copy.savedFilePath = nil
        return copy
    }
}

// MARK: - GRDB

extension ClipItem: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip_items"

    enum Columns: String, ColumnExpression {
        case id
        case contentType = "content_type"
        case textContent = "text_content"
        case richContent = "rich_content"
        case imagePath = "image_path"
        case filePaths = "file_paths"
        case sourceAppId = "source_app_id"
        case sourceAppName = "source_app_name"
        case createdAt = "created_at"
        case isPinned = "is_pinned"
        case isFavorite = "is_favorite"
        case hash
        case customTitle = "custom_title"
        case origin
        case ocrText = "ocr_text"
        case annotationPath = "annotation_path"
        case savedFilePath = "saved_file_path"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case textContent = "text_content"
        case richContent = "rich_content"
        case imagePath = "image_path"
        case filePaths = "file_paths"
        case sourceAppId = "source_app_id"
        case sourceAppName = "source_app_name"
        case createdAt = "created_at"
        case isPinned = "is_pinned"
        case isFavorite = "is_favorite"
        case hash
        case customTitle = "custom_title"
        case origin
        case ocrText = "ocr_text"
        case annotationPath = "annotation_path"
        case savedFilePath = "saved_file_path"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
    }
}
