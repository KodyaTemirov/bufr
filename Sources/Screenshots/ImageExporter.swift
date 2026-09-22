import AppKit
import UniformTypeIdentifiers

/// Image files leaving Bufr: "Save As…" and the names used for dragged files.
@MainActor
enum ImageExporter {
    /// The folder copy's name when there is one, otherwise "Screenshot 2026-09-23 at 14.05.12.png".
    nonisolated static func suggestedFilename(for item: ClipItem) -> String {
        if let path = item.savedFilePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        let prefix = item.isScreenshot ? L10n("screenshot.filename.prefix") : L10n("contentType.image")
        return ScreenshotFilenameFormatter.baseName(
            prefix: prefix,
            connector: L10n("screenshot.filename.at"),
            date: item.createdAt
        ) + ".png"
    }

    /// Real PNG bytes of an image item (history files written before 3.0 may hold TIFF).
    static func pngData(for item: ClipItem) async -> Data? {
        guard let path = item.imagePath,
              let data = await ImageStorage.shared.loadImageData(filename: path)
        else { return nil }
        return ImageEncoder.normalizedPNG(data)?.pngData
    }

    static func saveAs(_ item: ClipItem) async {
        guard let png = await pngData(for: item) else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: item)
        // An accessory app must be active for the panel to come to the front
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try png.write(to: url, options: .atomic)
            ToastPresenter.show(L10n("toast.saved"))
        } catch {
            NSSound.beep()
        }
    }
}
