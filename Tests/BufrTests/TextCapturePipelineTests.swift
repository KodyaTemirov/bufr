import AppKit
import Testing
@testable import Bufr

@MainActor
@Suite(.serialized)
struct TextCapturePipelineTests {
    static let suiteName = "com.bufr.tests.textCapture"

    let folder: URL
    let store: ClipItemStore
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bufr.tests.\(UUID().uuidString)"))
    let coordinator: ScreenshotCoordinator
    let notices = NoticeRecorder()

    init() throws {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        folder = try TestSupport.makeTempDirectory()
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
        let settings = ScreenshotSettings(defaults: defaults)
        settings.saveFolder = folder
        settings.playSound = false
        coordinator = ScreenshotCoordinator(
            settings: settings,
            permissions: PermissionsManager(defaults: defaults),
            ingestor: ClipIngestor(store: store, imageStorage: ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())),
            store: store,
            previousAreaStore: PreviousAreaStore(defaults: defaults),
            pasteboard: pasteboard,
            fallbackFolder: folder
        )
        let recorder = notices
        coordinator.notify = { message, _ in recorder.messages.append(message) }
    }

    private func outcome(_ image: CGImage) -> CaptureOutcome {
        CaptureOutcome(image: image, pointScale: 1, sourceAppId: "com.apple.Preview", sourceAppName: "Preview", region: nil, screenRect: nil)
    }

    @Test func recognizedTextGoesToClipboardAndHistory() async throws {
        let text = try #require(await coordinator.processTextCapture(outcome(TestImages.text("Hello Bufr"))))

        #expect(text.contains("Hello"))
        #expect(pasteboard.string(forType: .string) == text)
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
        #expect(store.items.first?.origin == .textCapture)
        #expect(store.items.first?.textContent == text)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(notices.messages.count == 1)
    }

    @Test func qrPayloadIsUsedWhenThereIsNoText() async throws {
        let text = await coordinator.processTextCapture(outcome(TestImages.qrCode("https://example.com/bufr")))

        #expect(text == "https://example.com/bufr")
        #expect(store.items.first?.contentType == .url)
    }

    @Test func nothingFoundLeavesHistoryAndClipboardAlone() async throws {
        let text = await coordinator.processTextCapture(outcome(TestImages.blank()))

        #expect(text == nil)
        #expect(store.items.isEmpty)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(notices.messages.count == 1)
    }
}

@MainActor
final class NoticeRecorder {
    var messages: [String] = []
}
