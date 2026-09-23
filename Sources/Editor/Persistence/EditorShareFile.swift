import CoreGraphics
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What "Share" sends: the editor's current result as a PNG named like the screenshot.
enum EditorShareFile {
    enum ShareError: Error {
        case renderingFailed
    }

    /// Each share gets its own folder, so the file keeps the screenshot's name and a second
    /// share never overwrites a file another app is still reading. The drag folder is purged
    /// at launch.
    static func write(
        _ document: AnnotationDocument,
        base: CGImage,
        filename: String,
        in directory: URL = DragFileResolver.dragDirectory
    ) throws -> URL {
        guard let flattened = AnnotationRenderer.renderFlattened(document, base: base),
              let png = ImageEncoder.pngData(from: flattened, pointScale: CGFloat(document.pointScale), downscaleToOneX: false)
        else { throw ShareError.renderingFailed }

        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try png.write(to: url)
        return url
    }
}

/// Rendered only when a sharing service asks for it (the share menu opening costs nothing).
struct EditorShareItem: Transferable, Sendable {
    let document: AnnotationDocument
    let base: CGImage
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(try EditorShareFile.write(item.document, base: item.base, filename: item.filename))
        }
    }
}
