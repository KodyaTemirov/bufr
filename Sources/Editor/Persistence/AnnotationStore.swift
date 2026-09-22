import CoreGraphics
import Foundation
import ImageIO

/// Loads and saves editable annotations for a history image.
///
/// Files in the images folder, all named after the image's UUID `u`:
/// - `u.png` — the flattened result every card, paste and export uses;
/// - `u_orig.png` — the untouched original, created on the first edit;
/// - `u.annotations.json` — the layers, so arrows can still be moved later.
@MainActor
final class AnnotationStore {
    struct Session {
        var document: AnnotationDocument
        let base: CGImage
    }

    enum StoreError: Error {
        case notAnImage
        case unreadableImage
        case renderingFailed
    }

    /// After every save/revert (pins and Quick Access refresh, OCR runs again)
    var onEdited: (ClipItem) -> Void = { _ in }

    private let store: ClipItemStore
    private let imageStorage: ImageStorage

    init(store: ClipItemStore, imageStorage: ImageStorage = .shared) {
        self.store = store
        self.imageStorage = imageStorage
    }

    private struct Names {
        let id: UUID
        let image: String
        let original: String
        let layers: String
    }

    private func names(for item: ClipItem) throws -> Names {
        guard let image = item.imagePath, let id = ImageStorage.uuid(fromImagePath: image) else {
            throw StoreError.notAnImage
        }
        let editorFiles = ImageStorage.editorFileNames(for: id)
        return Names(id: id, image: image, original: editorFiles[0], layers: editorFiles[1])
    }

    // MARK: - Open

    func open(_ item: ClipItem) async throws -> Session {
        let names = try names(for: item)

        if item.annotationPath != nil,
           let json = await imageStorage.loadImageData(filename: names.layers),
           let document = try? JSONDecoder().decode(AnnotationDocument.self, from: json),
           let originalData = await imageStorage.loadImageData(filename: names.original),
           let base = Self.decode(originalData) {
            return Session(document: document, base: base)
        }

        guard let data = await imageStorage.loadImageData(filename: names.image), let base = Self.decode(data) else {
            throw StoreError.unreadableImage
        }
        let document = AnnotationDocument(
            baseImageFilename: names.original,
            pixelWidth: base.width,
            pixelHeight: base.height,
            pointScale: Double(ImageEncoder.pointScale(of: data))
        )
        return Session(document: document, base: base)
    }

    // MARK: - Save

    @discardableResult
    func commit(_ document: AnnotationDocument, base: CGImage, for item: ClipItem) async throws -> ClipItem {
        let names = try names(for: item)

        // The first edit keeps the untouched original next to the image
        if await imageStorage.loadImageData(filename: names.original) == nil {
            guard let current = await imageStorage.loadImageData(filename: names.image) else { throw StoreError.unreadableImage }
            try await imageStorage.writeFile(ImageEncoder.normalizedPNG(current)?.pngData ?? current, named: names.original)
        }
        try await imageStorage.writeFile(try JSONEncoder().encode(document), named: names.layers)

        guard let flattened = AnnotationRenderer.renderFlattened(document, base: base),
              let png = ImageEncoder.pngData(from: flattened, pointScale: CGFloat(document.pointScale), downscaleToOneX: false)
        else { throw StoreError.renderingFailed }

        try await imageStorage.replaceImage(png, filename: names.image, thumbnailId: names.id)
        overwriteSavedFile(of: item, with: png)

        let updated = try store.applyEdit(
            id: item.id, hash: HashGenerator.sha256(png), annotationPath: names.layers,
            pixelWidth: flattened.width, pixelHeight: flattened.height
        )
        onEdited(updated)
        return updated
    }

    /// Back to the original: layers and the original copy are removed.
    @discardableResult
    func revert(_ item: ClipItem) async throws -> ClipItem {
        let names = try names(for: item)
        guard let original = await imageStorage.loadImageData(filename: names.original), let image = Self.decode(original) else {
            throw StoreError.unreadableImage
        }

        try await imageStorage.replaceImage(original, filename: names.image, thumbnailId: names.id)
        overwriteSavedFile(of: item, with: original)
        await imageStorage.removeFile(named: names.original)
        await imageStorage.removeFile(named: names.layers)

        let updated = try store.applyEdit(
            id: item.id, hash: HashGenerator.sha256(original), annotationPath: nil,
            pixelWidth: image.width, pixelHeight: image.height
        )
        onEdited(updated)
        return updated
    }

    /// Keeps the edited image and deletes the original and layers — after pixelating private
    /// data the unredacted pixels are then gone from disk too.
    @discardableResult
    func flatten(_ item: ClipItem) async throws -> ClipItem {
        let names = try names(for: item)
        await imageStorage.removeFile(named: names.original)
        await imageStorage.removeFile(named: names.layers)
        return try store.clearAnnotationPath(id: item.id)
    }

    // MARK: - Helpers

    /// The copy in the screenshots folder follows the edit (atomic, so Finder never sees half a file).
    private func overwriteSavedFile(of item: ClipItem, with png: Data) {
        guard let path = item.savedFilePath, FileManager.default.fileExists(atPath: path) else { return }
        try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
