import Foundation

/// What to show when Bufr starts.
enum LaunchNotices {
    static let setupVersionKey = "screenshotSetupVersion"
    static let accessibilityHintKey = "accessibilityHintShown"

    /// The screenshot setup assistant appears once per major version, starting with 3.0.
    static func shouldShowSetup(shownForVersion: String?, currentVersion: String) -> Bool {
        guard let current = AppVersion(string: currentVersion), current.major >= 3 else { return false }
        guard let shown = shownForVersion.flatMap({ AppVersion(string: $0) }) else { return true }
        return shown.major < current.major
    }

    /// After an update macOS may stop honouring the Screen Recording grant (ad-hoc signing).
    /// A fresh install is walked through setup instead.
    static func shouldHintPermissionLost(_ status: ScreenCapturePermission, showingSetup: Bool) -> Bool {
        status == .lostAfterUpdate && !showingSetup
    }
}
