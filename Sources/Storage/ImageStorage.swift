import AppKit
import Foundation

actor ImageStorage {
    static let shared = ImageStorage()

    private let imagesDir: URL
    private let thumbnailsDir: URL

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipo", isDirectory: true)

        imagesDir = support.appendingPathComponent("images", isDirectory: true)
        thumbnailsDir = support.appendingPathComponent("thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
    }

    // MARK: - Save

    func saveImage(_ data: Data, id: UUID) throws -> String {
        let filename = "\(id.uuidString).png"
        let fileURL = imagesDir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        // Generate thumbnail
        generateThumbnail(from: data, id: id)

        return filename
    }

    // MARK: - Load

    func loadImage(filename: String) -> NSImage? {
        let fileURL = imagesDir.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }

    func loadThumbnail(id: UUID) -> NSImage? {
        let filename = "\(id.uuidString)_thumb.png"
        let fileURL = thumbnailsDir.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }

    // MARK: - Delete

    func deleteImage(filename: String, id: UUID) {
        let imageURL = imagesDir.appendingPathComponent(filename)
        let thumbURL = thumbnailsDir.appendingPathComponent("\(id.uuidString)_thumb.png")
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: thumbURL)
    }

    // MARK: - Thumbnail

    private func generateThumbnail(from data: Data, id: UUID) {
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
    }
}
