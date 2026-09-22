import AppKit
import ScreenCaptureKit
import Testing
@testable import Bufr

@MainActor
@Suite(.serialized)
struct ScreenshotPipelineTests {
    static let suiteName = "com.bufr.tests.pipeline"

    let folder: URL
    let fallbackFolder: URL
    let store: ClipItemStore
    let settings: ScreenshotSettings
    let previousAreas: PreviousAreaStore
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bufr.tests.\(UUID().uuidString)"))
    let coordinator: ScreenshotCoordinator

    init() throws {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        folder = try TestSupport.makeTempDirectory().appendingPathComponent("Shots")
        fallbackFolder = try TestSupport.makeTempDirectory().appendingPathComponent("Fallback")
        store = ClipItemStore(database: try AppDatabase.makeEmpty())
        settings = ScreenshotSettings(defaults: defaults)
        settings.saveFolder = folder
        settings.playSound = false
        previousAreas = PreviousAreaStore(defaults: defaults)
        coordinator = ScreenshotCoordinator(
            settings: settings,
            permissions: PermissionsManager(defaults: defaults),
            ingestor: ClipIngestor(store: store, imageStorage: ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())),
            store: store,
            previousAreaStore: previousAreas,
            pasteboard: pasteboard,
            fallbackFolder: fallbackFolder
        )
    }

    private func outcome(region: CaptureRegion? = nil) -> CaptureOutcome {
        CaptureOutcome(
            image: TestImages.cgImage(width: 8, height: 6), pointScale: 2,
            sourceAppId: "com.apple.Safari", sourceAppName: "Safari", region: region
        )
    }

    @Test func captureBecomesScreenshotCardWithSavedFile() async throws {
        let item = try await coordinator.process(outcome())

        #expect(item.isScreenshot)
        #expect(item.sourceAppName == "Safari")
        #expect(item.pixelWidth == 8)
        #expect(store.items.first?.id == item.id)

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count == 1)
        #expect(item.savedFilePath == folder.appendingPathComponent(try #require(files.first)).path)
        #expect(try store.existingItem(hash: item.hash)?.savedFilePath == item.savedFilePath)
    }

    @Test func pngGoesToClipboardMarkedAsOwnWrite() async throws {
        _ = try await coordinator.process(outcome())

        #expect(pasteboard.types?.contains(.png) == true)
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
    }

    @Test func clipboardCopyCanBeTurnedOff() async throws {
        settings.copyToClipboard = false

        _ = try await coordinator.process(outcome())

        #expect(pasteboard.types?.contains(.png) != true)
    }

    @Test func areaIsRememberedAsPreviousArea() async throws {
        let region = CaptureRegion(displayUUID: "D", localRect: CGRect(x: 1, y: 2, width: 30, height: 40))

        _ = try await coordinator.process(outcome(region: region))

        #expect(previousAreas.load() == region)
    }

    @Test func unwritableFolderFallsBackAndStillRecordsCard() async throws {
        let blocker = try TestSupport.makeTempDirectory().appendingPathComponent("file")
        try Data([0]).write(to: blocker)
        settings.saveFolder = blocker.appendingPathComponent("sub") // parent is a file: cannot create

        let item = try await coordinator.process(outcome())

        #expect(store.items.first?.id == item.id)
        let saved = try #require(item.savedFilePath)
        #expect(saved.hasPrefix(fallbackFolder.path))
    }

    @Test func declinedConsentCountsAsPermissionError() {
        let declined = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)

        #expect(ScreenshotCoordinator.isPermissionError(declined))
        #expect(!ScreenshotCoordinator.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: 4)))
    }
}
