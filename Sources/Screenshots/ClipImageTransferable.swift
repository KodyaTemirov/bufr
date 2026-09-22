import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Drags an image item as a real PNG file (Finder, Mail, chat apps, upload fields).
struct ClipImageTransferable: Transferable {
    let item: ClipItem

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { transferable in
            let item = transferable.item
            let internalFile = item.imagePath.flatMap { ImageStorage.shared.fileURL(for: $0) }
            guard let url = try DragFileResolver.fileURL(
                savedFilePath: item.savedFilePath,
                internalFile: internalFile,
                suggestedName: ImageExporter.suggestedFilename(for: item),
                temporaryDirectory: DragFileResolver.dragDirectory
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(url)
        }
    }
}
