import CoreGraphics
import CoreText
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
    private let recognize: @Sendable (CGImage) async throws -> String
    private let pauseBetweenImages: Duration

    private var urgent: [UUID] = []
    private var worker: Task<Void, Never>?
    /// Recognitions in progress, so "Copy Text" joins the one the worker is already running
    private var inFlight: [UUID: Task<String?, Never>] = [:]
    /// Images Vision failed on; retried on the next launch instead of in a loop
    private var failed: Set<UUID> = []
    private var isEnabled = true
    private var isWarm = false

    init(
        repository: OCRRepository,
        imageStorage: ImageStorage,
        recognize: @escaping @Sendable (CGImage) async throws -> String = { try await OCRService().recognizeText(in: $0) },
        pauseBetweenImages: Duration = .milliseconds(250)
    ) {
        self.repository = repository
        self.imageStorage = imageStorage
        self.recognize = recognize
        self.pauseBetweenImages = pauseBetweenImages
    }

    /// Turning indexing off lets the current image finish: Vision can't be interrupted, and
    /// a cancelled worker would let a second one start on the same image.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
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
    /// (from half a minute to two); later launches take a few seconds. Doing it early keeps
    /// "Capture Text" fast, so it runs even when background indexing is off. The image has
    /// real text: on a blank one Vision finds no text regions and never loads the recognizer.
    func warmUp() async {
        guard !isWarm else { return }
        isWarm = true
        _ = try? await recognize(Self.warmUpImage)
    }

    /// For "Copy Text": the stored text, or a recognition now (joining one already running).
    func recognizeNow(_ id: UUID) async -> String? {
        await process(id)
    }

    /// Forgets every recognized text and starts over (e.g. after a Vision update).
    func reindexAll() {
        try? repository.resetAll()
        failed.removeAll()
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

    /// Stops after the current image once indexing is turned off. The loop condition and
    /// `worker = nil` run without a suspension in between, so re-enabling either finds
    /// this worker still looping or starts a fresh one, never both.
    private func drain() async {
        while isEnabled {
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
        while !urgent.isEmpty {
            let id = urgent.removeFirst()
            if !failed.contains(id) {
                return id
            }
        }
        return try? repository.nextPending(excluding: failed)
    }

    private func process(_ id: UUID) async -> String? {
        if let running = inFlight[id] {
            return await running.value
        }
        let task = Task { await self.recognizeAndStore(id) }
        inFlight[id] = task
        let text = await task.value
        inFlight[id] = nil
        return text
    }

    /// Recognizes one image and stores the text ("" when there is none or the file is gone,
    /// so the image is not retried forever). If the image is edited meanwhile, the text of
    /// the old pixels is dropped and the new image is recognized instead.
    private func recognizeAndStore(_ id: UUID) async -> String? {
        for _ in 0..<3 {
            guard let source = try? repository.source(for: id) else {
                return nil // item deleted meanwhile
            }
            if let stored = source.ocrText {
                return stored
            }

            var text = ""
            if let imagePath = source.imagePath, let url = imageStorage.fileURL(for: imagePath), let image = Self.loadImage(url) {
                do {
                    text = try await recognize(image)
                } catch {
                    logger.error("OCR failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    failed.insert(id)
                    return nil
                }
            }

            do {
                if try repository.setText(text, for: id, ifHash: source.hash) {
                    return text
                }
            } catch {
                logger.error("Saving OCR text failed: \(error.localizedDescription, privacy: .public)")
                return text
            }
        }
        return nil
    }

    private static let warmUpImage: CGImage = {
        let width = 480, height = 80
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let text = NSAttributedString(string: "Bufr Буфер 123", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        context.textPosition = CGPoint(x: 16, y: 24)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
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
