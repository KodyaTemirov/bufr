import Foundation

enum DragFileResolver {
    /// The file handed to a drop target: the copy in the screenshots folder when it still
    /// exists, otherwise a temporary PNG of the history file under a readable name
    /// (history files are named by UUID).
    static func fileURL(savedFilePath: String?, internalFile: URL?, suggestedName: String, temporaryDirectory: URL) throws -> URL? {
        let fileManager = FileManager.default
        if let savedFilePath, fileManager.fileExists(atPath: savedFilePath) {
            return URL(fileURLWithPath: savedFilePath)
        }
        guard let internalFile, fileManager.fileExists(atPath: internalFile.path) else { return nil }

        // Pre-3.0 history files may hold TIFF bytes under a .png name
        let data = try Data(contentsOf: internalFile)
        let png = ImageEncoder.normalizedPNG(data)?.pngData ?? data

        // A fresh folder per drag keeps the readable name free of collisions
        let folder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(suggestedName)
        try png.write(to: target)
        return target
    }
}
