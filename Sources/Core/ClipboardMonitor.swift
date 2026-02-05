import AppKit
import Foundation

@MainActor @Observable
final class ClipboardMonitor {
    private(set) var isMonitoring = false
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    private let clipItemStore: ClipItemStore
    private let exclusionManager: ExclusionManager
    private let pasteboard: NSPasteboard
    var playCopySound: Bool = false

    init(
        clipItemStore: ClipItemStore,
        exclusionManager: ExclusionManager,
        pasteboard: NSPasteboard = .general
    ) {
        self.clipItemStore = clipItemStore
        self.exclusionManager = exclusionManager
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for concealed/sensitive content
        if ExclusionManager.containsConcealedContent(pasteboard) {
            return
        }

        // Check if source app is excluded
        let appBundleId = ExclusionManager.frontmostAppBundleId()
        if exclusionManager.isExcluded(bundleId: appBundleId) {
            return
        }

        // Detect content type
        let contentType = ContentTypeDetector.detect(from: pasteboard)

        // Extract content
        let textContent = ContentTypeDetector.extractTextContent(from: pasteboard, type: contentType)
        let richContent = ContentTypeDetector.extractRichContent(from: pasteboard)
        let imageData = ContentTypeDetector.extractImageData(from: pasteboard)
        let filePaths = ContentTypeDetector.extractFilePaths(from: pasteboard)

        // Skip empty content
        if textContent == nil && imageData == nil && filePaths == nil {
            return
        }

        // Generate hash for deduplication
        let hash = HashGenerator.hashForClipContent(
            type: contentType,
            text: textContent,
            imageData: imageData,
            filePaths: filePaths
        )

        // Save image to disk if needed
        var imagePath: String?
        if contentType == .image, let imageData {
            let itemId = UUID()
            imagePath = try? awaitImageSave(data: imageData, id: itemId)
        }

        let item = ClipItem(
            contentType: contentType,
            textContent: textContent,
            richContent: richContent,
            imagePath: imagePath,
            filePaths: ClipItem.encodeFilePaths(filePaths ?? []),
            sourceAppId: appBundleId,
            sourceAppName: ExclusionManager.frontmostAppName(),
            hash: hash
        )

        do {
            try clipItemStore.insert(item)
            try clipItemStore.fetchItems()
            if playCopySound {
                SoundManager.playCopySound()
            }
        } catch {
            print("Failed to save clip item: \(error)")
        }
    }

    private nonisolated func awaitImageSave(data: Data, id: UUID) throws -> String {
        // Use a synchronous wrapper since ImageStorage is an actor
        nonisolated(unsafe) var result: String?
        nonisolated(unsafe) var saveError: Error?

        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable in
            do {
                result = try await ImageStorage.shared.saveImage(data, id: id)
            } catch {
                saveError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let saveError { throw saveError }
        return result ?? "\(id.uuidString).png"
    }
}
