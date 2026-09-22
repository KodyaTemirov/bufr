import Foundation

/// The single write path into history for clipboard content, screenshots and captured text.
/// Owns hashing, deduplication, PNG normalization and the file-name == item-id invariant.
@MainActor
final class ClipIngestor {
    struct ImageInput: Sendable {
        var id = UUID()
        var data: Data
        var origin: ClipOrigin
        var sourceAppId: String? = nil
        var sourceAppName: String? = nil
        var deduplicate = true
    }

    struct ContentInput: Sendable {
        var contentType: ContentType
        var textContent: String? = nil
        var richContent: Data? = nil
        var filePaths: [String]? = nil
        var origin: ClipOrigin
        var sourceAppId: String? = nil
        var sourceAppName: String? = nil
    }

    enum IngestError: Error {
        case unreadableImage
    }

    /// New image rows (not duplicates) — the OCR indexer picks them up first
    var onImageIngested: (UUID) -> Void = { _ in }

    private let store: ClipItemStore
    private let imageStorage: ImageStorage

    init(store: ClipItemStore, imageStorage: ImageStorage = .shared) {
        self.store = store
        self.imageStorage = imageStorage
    }

    // MARK: - Images

    @discardableResult
    func ingestImage(_ input: ImageInput) async throws -> ClipItem {
        let data = input.data
        // Hash the original bytes so copying the same image again still deduplicates
        let hash = await Task.detached(priority: .userInitiated) {
            HashGenerator.sha256(data)
        }.value

        if input.deduplicate, let existing = try store.existingItem(hash: hash) {
            return try store.touch(existing)
        }

        guard let image = await Task.detached(priority: .userInitiated, operation: {
            ImageEncoder.normalizedPNG(data)
        }).value else {
            throw IngestError.unreadableImage
        }

        let filename = try await imageStorage.saveImage(image.pngData, id: input.id)
        let item = ClipItem(
            id: input.id,
            contentType: .image,
            imagePath: filename,
            sourceAppId: input.sourceAppId,
            sourceAppName: input.sourceAppName,
            hash: hash,
            origin: input.origin,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )

        let saved: ClipItem
        do {
            saved = try store.insert(item, deduplicate: input.deduplicate)
        } catch {
            await imageStorage.deleteAssets(imagePath: filename, itemId: item.id)
            throw error
        }

        if saved.id != item.id {
            // Another ingest stored the same content while this one was encoding
            await imageStorage.deleteAssets(imagePath: filename, itemId: item.id)
        } else {
            onImageIngested(saved.id)
        }
        store.prependItem(saved)
        return saved
    }

    // MARK: - Text, rich text, URLs, colors, files

    @discardableResult
    func ingestContent(_ input: ContentInput) throws -> ClipItem {
        let hash = HashGenerator.hashForClipContent(
            type: input.contentType,
            text: input.textContent,
            imageData: nil,
            filePaths: input.filePaths
        )
        let item = ClipItem(
            contentType: input.contentType,
            textContent: input.textContent,
            richContent: input.richContent,
            filePaths: ClipItem.encodeFilePaths(input.filePaths ?? []),
            sourceAppId: input.sourceAppId,
            sourceAppName: input.sourceAppName,
            hash: hash,
            origin: input.origin
        )
        let saved = try store.insert(item)
        store.prependItem(saved)
        return saved
    }
}
