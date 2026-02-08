import Foundation
import GRDB
import SwiftUI

enum ContentType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case text
    case richText = "rich_text"
    case image
    case file
    case url
    case color

    var displayName: String {
        switch self {
        case .text:     L10n("contentType.text")
        case .richText: L10n("contentType.richText")
        case .image:    L10n("contentType.image")
        case .file:     L10n("contentType.file")
        case .url:      L10n("contentType.url")
        case .color:    L10n("contentType.color")
        }
    }

    var systemImage: String {
        switch self {
        case .text:     "doc.text"
        case .richText: "doc.richtext"
        case .image:    "photo"
        case .file:     "doc"
        case .url:      "link"
        case .color:    "paintpalette"
        }
    }

    var accentColor: Color {
        switch self {
        case .text:     .blue
        case .richText: .indigo
        case .image:    .green
        case .url:      .red
        case .file:     .gray
        case .color:    .purple
        }
    }
}
