import Foundation

/// What to show when Bufr starts.
enum LaunchNotices {
    static let setupVersionKey = "screenshotSetupVersion"
    static let permissionHintBuildKey = "permissionLostHintBuild"
    static let accessibilityHintBuildKey = "accessibilityHintBuild"

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// The screenshot setup assistant appears once per major version, starting with 3.0.
    static func shouldShowSetup(shownForVersion: String?, currentVersion: String) -> Bool {
        guard let current = AppVersion(string: currentVersion), current.major >= 3 else { return false }
        guard let shown = shownForVersion.flatMap({ AppVersion(string: $0) }) else { return true }
        return shown.major < current.major
    }

    /// Called when the assistant's window is closed (Done, Later, close button). Not when it is
    /// shown: its first step asks to restart Bufr, and it must come back after that restart.
    static func markSetupSeen(version: String, in defaults: UserDefaults) {
        defaults.set(version, forKey: setupVersionKey)
    }

    /// After an update macOS may stop honouring the Screen Recording grant (ad-hoc signing).
    /// A fresh install is walked through setup instead. Once per build, not at every launch.
    static func shouldHintPermissionLost(
        _ status: ScreenCapturePermission, showingSetup: Bool, hintedForBuild: String?, currentBuild: String
    ) -> Bool {
        status == .lostAfterUpdate && !showingSetup && hintedForBuild != currentBuild
    }

    /// Pasting needs Accessibility; with ad-hoc signing any update can silently drop it, so the
    /// hint comes back once per build.
    static func shouldHintAccessibility(trusted: Bool, hintedForBuild: String?, currentBuild: String) -> Bool {
        !trusted && hintedForBuild != currentBuild
    }
}
