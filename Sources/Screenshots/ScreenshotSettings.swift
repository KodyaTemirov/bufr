import Foundation
import Observation

enum AfterCaptureAction: String, CaseIterable, Sendable {
    case quickAccess
    case editor
    case pin
    case nothing
}

enum QuickAccessPosition: String, CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
}

/// Screenshot preferences, persisted in UserDefaults under `screenshot*` keys.
@MainActor @Observable
final class ScreenshotSettings {
    /// ~/Pictures/Bufr: unlike the Desktop, Pictures needs no extra privacy permission,
    /// which an ad-hoc signed app would lose on every update.
    static let defaultSaveFolder = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bufr", isDirectory: true)

    private enum Keys {
        static let saveFolder = "screenshotSaveFolder"
        static let filenamePrefix = "screenshotFilenamePrefix"
        static let copyToClipboard = "screenshotCopyToClipboard"
        static let playSound = "screenshotPlaySound"
        static let windowShadow = "screenshotWindowShadow"
        static let includeCursor = "screenshotIncludeCursor"
        static let retinaAtOneX = "screenshotRetinaAtOneX"
        static let afterCapture = "screenshotAfterCapture"
        static let quickAccessPosition = "screenshotQuickAccessPosition"
        static let quickAccessAutoClose = "screenshotQuickAccessAutoClose"
        static let ocrIndexingEnabled = "screenshotOCRIndexingEnabled"
    }

    /// Seconds before a Quick Access card closes itself; 0 = never
    static let autoCloseChoices = [0, 5, 10, 30, 60]

    @ObservationIgnored private let defaults: UserDefaults

    var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Keys.saveFolder) }
    }
    /// nil = the localized default ("Screenshot", "Снимок экрана", …)
    var customFilenamePrefix: String? {
        didSet { defaults.set(customFilenamePrefix, forKey: Keys.filenamePrefix) }
    }
    var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }
    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }
    /// Window captures keep the transparent macOS shadow
    var windowShadow: Bool {
        didSet { defaults.set(windowShadow, forKey: Keys.windowShadow) }
    }
    /// Fullscreen captures include the mouse pointer
    var includeCursor: Bool {
        didSet { defaults.set(includeCursor, forKey: Keys.includeCursor) }
    }
    /// Retina captures are saved at 1 pixel per point
    var retinaAtOneX: Bool {
        didSet { defaults.set(retinaAtOneX, forKey: Keys.retinaAtOneX) }
    }

    var afterCapture: AfterCaptureAction {
        didSet { defaults.set(afterCapture.rawValue, forKey: Keys.afterCapture) }
    }
    var quickAccessPosition: QuickAccessPosition {
        didSet { defaults.set(quickAccessPosition.rawValue, forKey: Keys.quickAccessPosition) }
    }
    var quickAccessAutoClose: Int {
        didSet { defaults.set(quickAccessAutoClose, forKey: Keys.quickAccessAutoClose) }
    }

    /// Recognize text in all history images so search finds words inside them
    var ocrIndexingEnabled: Bool {
        didSet { defaults.set(ocrIndexingEnabled, forKey: Keys.ocrIndexingEnabled) }
    }

    var filenamePrefix: String {
        let custom = customFilenamePrefix?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? L10n("screenshot.filename.prefix") : custom
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saveFolder = defaults.string(forKey: Keys.saveFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveFolder
        customFilenamePrefix = defaults.string(forKey: Keys.filenamePrefix)
        copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        playSound = defaults.object(forKey: Keys.playSound) as? Bool ?? true
        windowShadow = defaults.object(forKey: Keys.windowShadow) as? Bool ?? true
        includeCursor = defaults.object(forKey: Keys.includeCursor) as? Bool ?? false
        retinaAtOneX = defaults.object(forKey: Keys.retinaAtOneX) as? Bool ?? false
        afterCapture = AfterCaptureAction(rawValue: defaults.string(forKey: Keys.afterCapture) ?? "") ?? .quickAccess
        quickAccessPosition = QuickAccessPosition(rawValue: defaults.string(forKey: Keys.quickAccessPosition) ?? "") ?? .bottomLeft
        quickAccessAutoClose = defaults.object(forKey: Keys.quickAccessAutoClose) as? Int ?? 10
        ocrIndexingEnabled = defaults.object(forKey: Keys.ocrIndexingEnabled) as? Bool ?? true
    }

    func resetSaveFolder() {
        saveFolder = Self.defaultSaveFolder
    }
}
