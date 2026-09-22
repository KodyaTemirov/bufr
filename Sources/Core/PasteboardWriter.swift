import AppKit

extension NSPasteboard.PasteboardType {
    /// Marks pasteboard contents written by Bufr itself; ClipboardMonitor skips them
    /// because the item is already in history.
    static let bufrSelfWrite = NSPasteboard.PasteboardType("com.bufr.app.self-write")
}

/// The only place Bufr writes to a pasteboard. Every write carries the self-write marker.
@MainActor
enum PasteboardWriter {
    /// Keeps the lazy TIFF provider alive until the next image write.
    private static var tiffProvider: LazyTIFFProvider?

    static func writeText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markAsSelfWrite(pasteboard)
    }

    /// PNG is written up front; TIFF (for older apps) is produced only if someone asks for it,
    /// which avoids ~60 MB of TIFF for a 5K screenshot.
    static func writeImage(png: Data, to pasteboard: NSPasteboard = .general) {
        let provider = LazyTIFFProvider(pngData: png)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("1", forType: .bufrSelfWrite)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Accepts any ImageIO format (history files written before 3.0 may be TIFF).
    @discardableResult
    static func writeImage(anyImageData data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = ImageEncoder.normalizedPNG(data)?.pngData else { return false }
        writeImage(png: png, to: pasteboard)
        return true
    }

    /// Writes a non-image clip in its original format. Images go through `writeImage`.
    static func write(_ item: ClipItem, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        switch item.contentType {
        case .text, .color:
            pasteboard.setString(item.textContent ?? "", forType: .string)

        case .richText:
            if let richData = item.richContent {
                pasteboard.setData(richData, forType: .rtf)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .url:
            let urlString = item.textContent ?? ""
            pasteboard.setString(urlString, forType: .string)
            if let url = URL(string: urlString) {
                pasteboard.setString(url.absoluteString, forType: NSPasteboard.PasteboardType("public.url"))
            }

        case .file:
            let urls = item.filePathsArray.map { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSURL])

        case .image:
            assertionFailure("Use writeImage(png:) for images")
        }

        markAsSelfWrite(pasteboard)
    }

    private static func markAsSelfWrite(_ pasteboard: NSPasteboard) {
        pasteboard.setString("1", forType: .bufrSelfWrite)
    }
}

private final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    let pngData: Data

    init(pngData: Data) {
        self.pngData = pngData
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .tiff, let tiff = NSBitmapImageRep(data: pngData)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
