import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

private let logger = Logger(subsystem: "com.bufr.app", category: "PermissionsManager")

enum ScreenCapturePermission: Equatable, Sendable {
    case granted
    /// The system prompt has never been shown
    case notRequested
    case denied
    /// Granted for an earlier build: an ad-hoc signed update has a new code identity,
    /// and macOS keeps showing the old switch as ON while denying access
    case lostAfterUpdate
}

/// Screen Recording (captures) and Accessibility (paste) status, prompts and System Settings links.
@MainActor @Observable
final class PermissionsManager {
    private(set) var screenCapture: ScreenCapturePermission = .notRequested
    private(set) var accessibilityGranted = false

    private enum Keys {
        static let requested = "screenCaptureRequested"
        static let grantedBuild = "screenCaptureGrantedBuild"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    nonisolated static func status(granted: Bool, requestedBefore: Bool, grantedBuild: String?, currentBuild: String) -> ScreenCapturePermission {
        if granted { return .granted }
        if let grantedBuild, grantedBuild != currentBuild { return .lostAfterUpdate }
        return requestedBefore ? .denied : .notRequested
    }

    func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted {
            defaults.set(currentBuild, forKey: Keys.grantedBuild)
        }
        screenCapture = Self.status(
            granted: granted,
            requestedBefore: defaults.bool(forKey: Keys.requested),
            grantedBuild: defaults.string(forKey: Keys.grantedBuild),
            currentBuild: currentBuild
        )
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time; macOS never prompts twice, so later calls open
    /// System Settings instead.
    func requestScreenCapture() {
        if defaults.bool(forKey: Keys.requested) {
            openScreenCaptureSettings()
        } else {
            defaults.set(true, forKey: Keys.requested)
            _ = CGRequestScreenCaptureAccess()
        }
        refresh()
    }

    func requestAccessibility() {
        // The literal key avoids referencing the kAXTrustedCheckOptionPrompt global (Swift 6)
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refresh()
    }

    /// Removes the stale Screen Recording entry left by an update, so the next request prompts again.
    func resetScreenCapturePermission() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleId]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
        }
        defaults.set(false, forKey: Keys.requested)
        defaults.removeObject(forKey: Keys.grantedBuild)
        refresh()
    }

    // MARK: - System Settings

    func openScreenCaptureSettings() {
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ])
    }

    func openAccessibilitySettings() {
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    func openKeyboardShortcutsSettings() {
        open([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        ])
    }

    private func open(_ candidates: [String]) {
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
