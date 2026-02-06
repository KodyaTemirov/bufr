import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.bufr.app", category: "ClipboardMonitor")

@MainActor @Observable
final class ClipboardMonitor {
    private(set) var isMonitoring = false
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    private static let maxImageSize = 50 * 1024 * 1024 // 50 MB

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

        // Save image to disk if needed (skip oversized images)
        if contentType == .image, let imageData, imageData.count <= Self.maxImageSize {
            Task {
                let itemId = UUID()
                let imagePath = try? await ImageStorage.shared.saveImage(imageData, id: itemId)
                self.saveClipItem(
                    contentType: contentType, textContent: textContent,
                    richContent: richContent, imagePath: imagePath,
                    filePaths: filePaths, appBundleId: appBundleId, hash: hash
                )
            }
        } else {
            saveClipItem(
                contentType: contentType, textContent: textContent,
                richContent: richContent, imagePath: nil,
                filePaths: filePaths, appBundleId: appBundleId, hash: hash
            )
        }
    }

    private func saveClipItem(
        contentType: ContentType, textContent: String?,
        richContent: Data?, imagePath: String?,
        filePaths: [String]?, appBundleId: String?, hash: String
    ) {
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
            logger.error("Failed to save clip item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
