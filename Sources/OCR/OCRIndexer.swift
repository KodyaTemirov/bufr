import CoreGraphics
import Foundation
import ImageIO
import OSLog

private let logger = Logger(subsystem: "com.bufr.app", category: "OCRIndexer")

/// Recognizes text in every history image in the background so search finds words inside
/// screenshots. New images go first, then older ones are backfilled one at a time.
/// Pauses while the Mac is in Low Power Mode or running hot.
actor OCRIndexer {
    /// Larger images are downsampled first; text stays readable and memory stays bounded
    static let maxPixelSize = 6144

    private let repository: OCRRepository
    private let imageStorage: ImageStorage
    private let service: OCRService
    private let pauseBetweenImages: Duration

    private var urgent: [UUID] = []
    private var worker: Task<Void, Never>?
    private var isEnabled = true
    private var isWarm = false

    init(
        repository: OCRRepository,
        imageStorage: ImageStorage,
        service: OCRService = OCRService(),
        pauseBetweenImages: Duration = .milliseconds(250)
    ) {
        self.repository = repository
        self.imageStorage = imageStorage
        self.service = service
        self.pauseBetweenImages = pauseBetweenImages
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            worker?.cancel()
            worker = nil
        }
    }

    /// A freshly added image jumps the queue.
    func enqueue(_ id: UUID) {
        urgent.removeAll { $0 == id }
        urgent.insert(id, at: 0)
        start()
    }

    func startBackfill() {
        start()
    }

    /// The first recognition after installing or updating Bufr compiles Vision's models
    /// (about half a minute); later launches take a few seconds. Doing it early keeps
    /// "Capture Text" fast when the user needs it.
    func warmUp() async {
        guard isEnabled, !isWarm else { return }
        isWarm = true
        _ = try? await service.recognizeText(in: Self.warmUpImage)
    }

    /// For "Copy Text" on an image that has not been indexed yet.
    func recognizeNow(_ id: UUID) async -> String? {
        if let text = try? repository.text(for: id) {
            return text
        }
        return await process(id)
    }

    /// Forgets every recognized text and starts over (e.g. after a Vision update).
    func reindexAll() {
        try? repository.resetAll()
        start()
    }

    func progress() -> OCRRepository.Progress? {
        try? repository.progress()
    }

    /// Returns once the queue is empty (tests, "re-index" UI).
    func waitUntilIdle() async {
        await worker?.value
    }

    // MARK: - Worker

    private func start() {
        guard isEnabled, worker == nil else { return }
        worker = Task(priority: .background) {
            await self.drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled && isEnabled {
            if Self.shouldYield {
                try? await Task.sleep(for: .seconds(30))
                continue
            }
            guard let id = nextID() else { break }
            _ = await process(id)
            try? await Task.sleep(for: pauseBetweenImages)
        }
        worker = nil
    }

    private func nextID() -> UUID? {
        if !urgent.isEmpty {
            return urgent.removeFirst()
        }
        return try? repository.nextPending()
    }

    /// Recognizes one image and stores the text ("" when there is none or the file is gone,
    /// so the image is not retried forever).
    private func process(_ id: UUID) async -> String? {
        guard let imagePath = try? repository.imagePath(for: id) else {
            return nil // item deleted meanwhile
        }

        var text = ""
        if let imagePath, let url = imageStorage.fileURL(for: imagePath), let image = Self.loadImage(url) {
            do {
                text = try await service.recognizeText(in: image)
            } catch {
                logger.error("OCR failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try repository.setText(text, for: id)
        } catch {
            logger.error("Saving OCR text failed: \(error.localizedDescription, privacy: .public)")
        }
        return text
    }

    private static let warmUpImage: CGImage = {
        let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        return context.makeImage()!
    }()

    private static var shouldYield: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
