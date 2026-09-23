import AppKit
import ApplicationServices
import CoreGraphics
import OSLog
import Security

private let logger = Logger(subsystem: "com.bufr.app", category: "PermissionsManager")

enum ScreenCapturePermission: Equatable, Sendable {
    case granted
    /// The system prompt has never been shown
    case notRequested
    case denied
    /// Granted to an earlier binary: an ad-hoc signed update or rebuild has a new code
    /// identity, and macOS keeps showing the old switch as ON while denying access
    case lostAfterUpdate
}

/// Screen Recording (captures) and Accessibility (paste) status, prompts and System Settings links.
@MainActor @Observable
final class PermissionsManager {
    private(set) var screenCapture: ScreenCapturePermission = .notRequested
    private(set) var accessibilityGranted = false

    private enum Keys {
        static let requested = "screenCaptureRequested"
        /// The binary (code directory hash) the grant was last seen working for
        static let grantedIdentity = "screenCaptureGrantedIdentity"
        /// Before identities: the CFBundleVersion — misses rebuilds that keep the version
        static let legacyGrantedBuild = "screenCaptureGrantedBuild"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let codeIdentity: String
    @ObservationIgnored private let preflight: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        codeIdentity: String? = CodeIdentity.current,
        preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.defaults = defaults
        self.codeIdentity = codeIdentity ?? "unknown"
        self.preflight = preflight
        refresh()
    }

    nonisolated static func status(granted: Bool, requestedBefore: Bool, grantedIdentity: String?, currentIdentity: String) -> ScreenCapturePermission {
        if granted { return .granted }
        if let grantedIdentity, grantedIdentity != currentIdentity { return .lostAfterUpdate }
        return requestedBefore ? .denied : .notRequested
    }

    func refresh() {
        let granted = preflight()
        if granted {
            defaults.set(codeIdentity, forKey: Keys.grantedIdentity)
            defaults.removeObject(forKey: Keys.legacyGrantedBuild)
        }
        // A grant recorded by build number belonged to an earlier binary of some kind
        let legacyGrant = defaults.string(forKey: Keys.legacyGrantedBuild).map { "build-\($0)" }
        screenCapture = Self.status(
            granted: granted,
            requestedBefore: defaults.bool(forKey: Keys.requested),
            grantedIdentity: defaults.string(forKey: Keys.grantedIdentity) ?? legacyGrant,
            currentIdentity: codeIdentity
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
        defaults.removeObject(forKey: Keys.grantedIdentity)
        defaults.removeObject(forKey: Keys.legacyGrantedBuild)
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
}

/// Which binary is running. Ad-hoc signed grants (Screen Recording, Accessibility) are tied to
/// this hash, so every build — even with the same version number — starts without them.
enum CodeIdentity {
    static let current: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }()
}
