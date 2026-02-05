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
        case .text:     "Текст"
        case .richText: "Форматированный"
        case .image:    "Изображение"
        case .file:     "Файл"
        case .url:      "Ссылка"
        case .color:    "Цвет"
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
