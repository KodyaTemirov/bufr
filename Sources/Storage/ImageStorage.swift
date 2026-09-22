import AppKit
import Foundation

actor ImageStorage {
    static let shared = ImageStorage(baseDirectory: AppPaths.support)

    private let imagesDir: URL
    private let thumbnailsDir: URL
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()
    /// Background thumbnail jobs, so a delete can wait for one instead of racing it
    private var pendingThumbnails: [UUID: Task<Void, Never>] = [:]

    init(baseDirectory: URL) {
        imagesDir = baseDirectory.appendingPathComponent("images", isDirectory: true)
        thumbnailsDir = baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // MARK: - Save

    func saveImage(_ data: Data, id: UUID) throws -> String {
        let filename = "\(id.uuidString).png"
        let fileURL = imagesDir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        // Generate thumbnail in background — don't block save
        let thumbDir = thumbnailsDir
        pendingThumbnails[id] = Task.detached(priority: .utility) { [weak self] in
            Self.generateThumbnailSync(from: data, id: id, thumbnailsDir: thumbDir)
            await self?.thumbnailFinished(id)
        }

        return filename
    }

    private func thumbnailFinished(_ id: UUID) {
        pendingThumbnails[id] = nil
    }

    // MARK: - Validation

    private func isValidFilename(_ filename: String) -> Bool {
        Self.isValidFilename(filename)
    }

    private nonisolated static func isValidFilename(_ filename: String) -> Bool {
        !filename.contains("/") && !filename.contains("..") && !filename.isEmpty
    }

    /// Location of a history image (e.g. for drag-out); nil for names that could escape the folder.
    nonisolated func fileURL(for filename: String) -> URL? {
        guard Self.isValidFilename(filename) else { return nil }
        return imagesDir.appendingPathComponent(filename)
    }

    // MARK: - Load

    func loadImageData(filename: String) -> Data? {
        guard isValidFilename(filename) else { return nil }
        let fileURL = imagesDir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    func loadImage(filename: String) -> NSImage? {
        guard isValidFilename(filename) else { return nil }
        let fileURL = imagesDir.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }

    func loadThumbnail(id: UUID) -> NSImage? {
        let key = id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let filename = "\(id.uuidString)_thumb.png"
        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: fileURL) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Editor files

    /// Writes a file next to the images (editor layers, the untouched original).
    func writeFile(_ data: Data, named filename: String) throws {
        guard isValidFilename(filename) else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = imagesDir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func removeFile(named filename: String) {
        guard isValidFilename(filename) else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(filename))
    }

    /// Replaces an image in place (after editing) and rebuilds its thumbnail before returning,
    /// so cards reloading right after see the new picture.
    func replaceImage(_ data: Data, filename: String, thumbnailId: UUID) async throws {
        try writeFile(data, named: filename)
        await pendingThumbnails[thumbnailId]?.value
        Self.generateThumbnailSync(from: data, id: thumbnailId, thumbnailsDir: thumbnailsDir)
        thumbnailCache.removeObject(forKey: thumbnailId.uuidString as NSString)
    }

    // MARK: - Delete

    /// Removes an item's image and thumbnail. Rows created before 3.0 used a different UUID
    /// for the file than for the item, so thumbnails for both UUIDs are removed.
    func deleteAssets(imagePath: String?, itemId: UUID) async {
        var ids: Set<UUID> = [itemId]
        if let imagePath, isValidFilename(imagePath) {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(imagePath))
            if let fileId = Self.uuid(fromImagePath: imagePath) {
                ids.insert(fileId)
            }
        }
        for id in ids {
            // Editor layers and the untouched original
            for name in Self.editorFileNames(for: id) {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
            }
            // A thumbnail still being generated would otherwise be written after this delete
            await pendingThumbnails[id]?.value
            try? FileManager.default.removeItem(at: thumbnailsDir.appendingPathComponent("\(id.uuidString)_thumb.png"))
            thumbnailCache.removeObject(forKey: id.uuidString as NSString)
        }
    }

    nonisolated static func editorFileNames(for id: UUID) -> [String] {
        ["\(id.uuidString)_orig.png", "\(id.uuidString).annotations.json"]
    }

    /// "<uuid>.png" → uuid
    nonisolated static func uuid(fromImagePath imagePath: String) -> UUID? {
        UUID(uuidString: (imagePath as NSString).deletingPathExtension)
    }

    func deleteAllImages() {
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.removeItem(at: thumbnailsDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // MARK: - Thumbnail

    private nonisolated static func generateThumbnailSync(from data: Data, id: UUID, thumbnailsDir: URL) {
        let maxSize: CGFloat = 400

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }

        let filename = "\(id.uuidString)_thumb.png"
        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        try? pngData.write(to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
