import AppKit
import OSLog
import ScreenCaptureKit

private let logger = Logger(subsystem: "com.bufr.app", category: "Screenshots")

/// Entry point for every screenshot action: permission check, capture session, and the
/// post-capture pipeline (history card, file in the screenshots folder, clipboard).
@MainActor
final class ScreenshotCoordinator {
    enum PipelineError: Error {
        case encodingFailed
    }

    /// Hides Bufr's own panel and preview before the screen is frozen
    var prepareForCapture: () -> Void = {}
    /// Explains how to grant Screen Recording
    var showPermissionGuide: () -> Void = {}

    var isCapturing: Bool { session.isActive }

    private let settings: ScreenshotSettings
    private let permissions: PermissionsManager
    private let ingestor: ClipIngestor
    private let store: ClipItemStore
    private let previousAreaStore: PreviousAreaStore
    private let pasteboard: NSPasteboard
    private let fallbackFolder: URL
    private let session = CaptureSessionController()

    init(
        settings: ScreenshotSettings,
        permissions: PermissionsManager,
        ingestor: ClipIngestor,
        store: ClipItemStore,
        previousAreaStore: PreviousAreaStore = PreviousAreaStore(defaults: .standard),
        pasteboard: NSPasteboard = .general,
        fallbackFolder: URL = ScreenshotSettings.defaultSaveFolder
    ) {
        self.settings = settings
        self.permissions = permissions
        self.ingestor = ingestor
        self.store = store
        self.previousAreaStore = previousAreaStore
        self.pasteboard = pasteboard
        self.fallbackFolder = fallbackFolder
    }

    // MARK: - Capture

    /// A second request while a selection is on screen cancels it (like pressing the hotkey twice).
    /// Menu items pass `afterMenuCloses` so the menu is gone from the frozen frame.
    func capture(_ mode: CaptureMode, afterMenuCloses: Bool = false) {
        if session.isActive {
            session.cancel()
            return
        }

        permissions.refresh()
        guard permissions.screenCapture == .granted else {
            if permissions.screenCapture == .notRequested {
                permissions.requestScreenCapture()
            }
            showPermissionGuide()
            return
        }

        prepareForCapture()
        Task {
            if afterMenuCloses {
                try? await Task.sleep(for: .milliseconds(200))
            }
            do {
                let options = CaptureSessionController.Options(
                    showsCursor: settings.includeCursor,
                    windowShadow: settings.windowShadow,
                    showMagnifier: true,
                    previousArea: previousAreaStore.load()
                )
                guard let outcome = try await session.capture(mode, options: options) else { return }
                try await process(outcome)
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                if Self.isPermissionError(error) {
                    showPermissionGuide()
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    /// macOS refused the capture (e.g. the periodic consent alert was declined) even though the
    /// Screen Recording switch is on.
    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    // MARK: - Pipeline

    /// Turns a capture into a history card, a PNG in the screenshots folder and (optionally)
    /// the clipboard content.
    @discardableResult
    func process(_ outcome: CaptureOutcome) async throws -> ClipItem {
        if settings.playSound {
            ShutterSound.play()
        }

        let image = outcome.image
        let pointScale = outcome.pointScale
        let downscale = settings.retinaAtOneX
        guard let png = await Task.detached(priority: .userInitiated, operation: {
            ImageEncoder.pngData(from: image, pointScale: pointScale, downscaleToOneX: downscale)
        }).value else {
            throw PipelineError.encodingFailed
        }

        var item = try await ingestor.ingestImage(.init(
            data: png,
            origin: .screenshot,
            sourceAppId: outcome.sourceAppId,
            sourceAppName: outcome.sourceAppName,
            deduplicate: false // two identical captures are two events
        ))

        if let fileURL = saveToFolder(png) {
            try store.setSavedFilePath(fileURL.path, for: item.id)
            item.savedFilePath = fileURL.path
        }
        if settings.copyToClipboard {
            PasteboardWriter.writeImage(png: png, to: pasteboard)
        }
        if let region = outcome.region {
            previousAreaStore.save(region)
        }
        return item
    }

    private func saveToFolder(_ png: Data) -> URL? {
        let baseName = ScreenshotFilenameFormatter.baseName(
            prefix: settings.filenamePrefix,
            connector: L10n("screenshot.filename.at"),
            date: Date()
        )
        do {
            return try ScreenshotFileWriter.write(png, to: settings.saveFolder, baseName: baseName)
        } catch {
            logger.error("Saving to \(self.settings.saveFolder.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            // The chosen folder was removed or is not writable: keep the file anyway
            guard settings.saveFolder.standardizedFileURL != fallbackFolder.standardizedFileURL else { return nil }
            return try? ScreenshotFileWriter.write(png, to: fallbackFolder, baseName: baseName)
        }
    }

    // MARK: - Finder

    func openScreenshotsFolder() {
        try? FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(settings.saveFolder)
    }

    func revealInFinder(_ item: ClipItem) {
        guard let path = item.savedFilePath, FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
