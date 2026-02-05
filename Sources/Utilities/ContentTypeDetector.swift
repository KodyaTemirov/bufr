import AppKit

struct ContentTypeDetector {
    static func detect(from pasteboard: NSPasteboard) -> ContentType {
        guard let types = pasteboard.types else { return .text }

        // Priority: image > file > url > color > richText > text
        if types.contains(.tiff) || types.contains(.png) {
            return .image
        }

        if types.contains(.fileURL) {
            return .file
        }

        if types.contains(.URL) || types.contains(NSPasteboard.PasteboardType("public.url")) {
            return .url
        }

        if let text = pasteboard.string(forType: .string), ColorExtractor.isColor(text) {
            return .color
        }

        if types.contains(.rtf) || types.contains(.html) {
            return .richText
        }

        return .text
    }

    static func extractTextContent(from pasteboard: NSPasteboard, type: ContentType) -> String? {
        switch type {
        case .text, .color:
            return pasteboard.string(forType: .string)
        case .richText:
            return pasteboard.string(forType: .string)
        case .url:
            return pasteboard.string(forType: .string)
                ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.url"))
        case .file:
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
                return urls.map(\.lastPathComponent).joined(separator: ", ")
            }
            return nil
        case .image:
            return nil
        }
    }

    static func extractRichContent(from pasteboard: NSPasteboard) -> Data? {
        if let rtfData = pasteboard.data(forType: .rtf) {
            return rtfData
        }
        if let htmlData = pasteboard.data(forType: .html) {
            return htmlData
        }
        return nil
    }

    static func extractImageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        return nil
    }

    static func extractFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return nil
        }
        let paths = urls.map(\.path)
        return paths.isEmpty ? nil : paths
    }
}
