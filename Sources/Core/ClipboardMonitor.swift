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

    private let ingestor: ClipIngestor
    private let exclusionManager: ExclusionManager
    private let pasteboard: NSPasteboard
    var playCopySound: Bool = false

    init(
        ingestor: ClipIngestor,
        exclusionManager: ExclusionManager,
        pasteboard: NSPasteboard = .general
    ) {
        self.ingestor = ingestor
        self.exclusionManager = exclusionManager
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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

    // MARK: - Change detection

    /// Internal (not private) so tests can drive it without the timer.
    func checkForChanges() {
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
        let appName = ExclusionManager.frontmostAppName()

        let contentType = ContentTypeDetector.detect(from: pasteboard)

        if contentType == .image {
            // Oversized or unreadable images are skipped: a card without an image is useless
            guard let imageData = ContentTypeDetector.extractImageData(from: pasteboard),
                  imageData.count <= Self.maxImageSize else { return }
            let input = ClipIngestor.ImageInput(
                data: imageData, origin: .clipboard,
                sourceAppId: appBundleId, sourceAppName: appName
            )
            Task {
                do {
                    try await self.ingestor.ingestImage(input)
                    self.playSoundIfEnabled()
                } catch {
                    logger.error("Failed to save image clip: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        let input = ClipIngestor.ContentInput(
            contentType: contentType,
            textContent: ContentTypeDetector.extractTextContent(from: pasteboard, type: contentType),
            richContent: ContentTypeDetector.extractRichContent(from: pasteboard),
            filePaths: ContentTypeDetector.extractFilePaths(from: pasteboard),
            origin: .clipboard,
            sourceAppId: appBundleId,
            sourceAppName: appName
        )

        // Skip empty content
        guard input.textContent != nil || input.filePaths != nil else { return }

        do {
            try ingestor.ingestContent(input)
            playSoundIfEnabled()
        } catch {
            logger.error("Failed to save clip item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func playSoundIfEnabled() {
        if playCopySound {
            SoundManager.playCopySound()
        }
    }
}
