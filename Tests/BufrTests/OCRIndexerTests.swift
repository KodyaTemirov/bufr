import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Bufr

@MainActor
struct OCRIndexerTests {
    let database: AppDatabase
    let store: ClipItemStore
    let storage: ImageStorage
    let ingestor: ClipIngestor
    let repository: OCRRepository
    let indexer: OCRIndexer

    init() throws {
        database = try AppDatabase.makeEmpty()
        store = ClipItemStore(database: database)
        storage = ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        ingestor = ClipIngestor(store: store, imageStorage: storage)
        repository = OCRRepository(database: database)
        indexer = OCRIndexer(repository: repository, imageStorage: storage, pauseBetweenImages: .zero)
    }

    private func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func backfillRecognizesTextInExistingImages() async throws {
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.text("Invoice 4521")), origin: .clipboard))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id)?.contains("Invoice") == true)
        #expect(try store.search(query: "invoice").map(\.id) == [item.id])
    }

    @Test func imageWithoutTextIsMarkedDone() async throws {
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.blank()), origin: .screenshot))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == "")
        #expect(try repository.nextPending() == nil)
    }

    /// The history file can vanish (deleted card, cleaned folder) while the item is queued.
    @Test func missingFileIsSkipped() async throws {
        let item = try store.insert(ClipItem(contentType: .image, imagePath: "missing.png", hash: "gone"))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == "")
    }

    @Test func disabledIndexerLeavesImagesPending() async throws {
        let item = try store.insert(ClipItem(contentType: .image, imagePath: "missing.png", hash: "off"))

        await indexer.setEnabled(false)
        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == nil)
        #expect(try repository.progress() == OCRRepository.Progress(done: 0, total: 1))
    }

    // MARK: - Concurrency (fake recognizer, no Vision)

    /// Like Vision, the fake ignores task cancellation; every call returns "call <n>".
    private func fakeIndexer(delay: Duration, calls: RecognitionCounter) -> OCRIndexer {
        OCRIndexer(repository: repository, imageStorage: storage, recognize: { _ in
            let number = await calls.increment()
            await RecognitionCounter.uncancellableSleep(delay)
            return [OCRTextAssembler.Line(text: "call \(number)", box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.1))]
        }, pauseBetweenImages: .zero)
    }

    /// Turning recognition off and on during a recognition must not start a second worker
    /// that recognizes the same image again.
    @Test func togglingDuringRecognitionDoesNotDoubleTheWork() async throws {
        let calls = RecognitionCounter()
        let indexer = fakeIndexer(delay: .milliseconds(150), calls: calls)
        for n in 0..<3 {
            _ = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 10 + n, height: 10)), origin: .clipboard))
        }

        await indexer.startBackfill()
        await calls.waitForFirstCall()
        await indexer.setEnabled(false)
        await indexer.setEnabled(true)
        try await Task.sleep(for: .milliseconds(1000))
        await indexer.waitUntilIdle()

        #expect(await calls.count == 3)
        #expect(try repository.progress() == OCRRepository.Progress(done: 3, total: 3))
    }

    /// "Copy Text" right after a capture waits for the recognition already running.
    @Test func recognizeNowJoinsTheRunningRecognition() async throws {
        let calls = RecognitionCounter()
        let indexer = fakeIndexer(delay: .milliseconds(200), calls: calls)
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 20, height: 10)), origin: .screenshot))

        await indexer.enqueue(item.id)
        await calls.waitForFirstCall()
        let text = await indexer.recognizeNow(item.id)
        await indexer.waitUntilIdle()

        #expect(text == "call 1")
        #expect(await calls.count == 1)
    }

    /// An image edited (e.g. pixelated) while being recognized must not keep the old image's
    /// text; it is recognized again. The first recognition is held open until the edit is
    /// made, so the test doesn't depend on timing.
    @Test func resultForAnOutdatedImageIsDropped() async throws {
        let calls = RecognitionCounter()
        let gate = RecognitionGate()
        let indexer = OCRIndexer(repository: repository, imageStorage: storage, recognize: { _ in
            let number = await calls.increment()
            if number == 1 {
                await gate.wait()
            }
            return [OCRTextAssembler.Line(text: "call \(number)", box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.1))]
        }, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 30, height: 10)), origin: .screenshot))

        await indexer.enqueue(item.id)
        await calls.waitForFirstCall()
        _ = try store.applyEdit(id: item.id, hash: "edited", annotationPath: nil, pixelWidth: 30, pixelHeight: 10)
        await gate.open()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == "call 2")
    }

    /// Vision can fail (e.g. while it compiles its models under load). The image must stay
    /// pending for a later retry instead of being marked "no text" for good.
    @Test func failedRecognitionLeavesTheImagePending() async throws {
        let calls = RecognitionCounter()
        let indexer = OCRIndexer(repository: repository, imageStorage: storage, recognize: { _ in
            _ = await calls.increment()
            throw CocoaError(.featureUnsupported)
        }, pauseBetweenImages: .zero)
        let item = try await ingestor.ingestImage(.init(data: png(TestImages.cgImage(width: 40, height: 10)), origin: .screenshot))

        await indexer.startBackfill()
        await indexer.waitUntilIdle()

        #expect(try repository.text(for: item.id) == nil)
        #expect(await calls.count == 1) // not retried in a loop
    }

    /// Warm-up must load the recognizer even when background indexing is off: "Capture Text"
    /// still needs it.
    @Test func warmUpRunsOnceEvenWithIndexingOff() async throws {
        let calls = RecognitionCounter()
        let indexer = fakeIndexer(delay: .zero, calls: calls)

        await indexer.setEnabled(false)
        await indexer.warmUp()
        await indexer.warmUp()

        #expect(await calls.count == 1)
    }
}

actor RecognitionCounter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func waitForFirstCall() async {
        while count == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    static func uncancellableSleep(_ duration: Duration) async {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }
}

/// Holds a fake recognition until the test opens it.
actor RecognitionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
