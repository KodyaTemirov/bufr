import AppKit
import SwiftUI
import Testing
@testable import Bufr

struct LaunchNoticesTests {
    private func hintsPermission(_ status: ScreenCapturePermission, setup: Bool = false, hinted: String? = nil, build: String = "31") -> Bool {
        LaunchNotices.shouldHintPermissionLost(status, showingSetup: setup, hintedForBuild: hinted, currentBuild: build)
    }

    private func hintsAccessibility(trusted: Bool, hinted: String?, build: String) -> Bool {
        LaunchNotices.shouldHintAccessibility(trusted: trusted, hintedForBuild: hinted, currentBuild: build)
    }

    @Test func setupAppearsOnFirstLaunchOfVersionThree() {
        #expect(LaunchNotices.shouldShowSetup(shownForVersion: nil, currentVersion: "3.0.0"))
        #expect(LaunchNotices.shouldShowSetup(shownForVersion: "2.0.0", currentVersion: "3.0.0"))
    }

    @Test func setupAppearsOnlyOncePerMajorVersion() {
        #expect(!LaunchNotices.shouldShowSetup(shownForVersion: "3.0.0", currentVersion: "3.0.0"))
        #expect(!LaunchNotices.shouldShowSetup(shownForVersion: "3.0.0", currentVersion: "3.2.1"))
    }

    @Test func noSetupBeforeVersionThreeOrWithoutAVersion() {
        #expect(!LaunchNotices.shouldShowSetup(shownForVersion: nil, currentVersion: "2.0.0"))
        #expect(!LaunchNotices.shouldShowSetup(shownForVersion: nil, currentVersion: "dev"))
    }

    /// A fresh install gets the setup assistant instead; only an update that lost the grant hints.
    @Test func permissionLostHintOnlyAfterUpdate() {
        #expect(hintsPermission(.lostAfterUpdate))
        #expect(!hintsPermission(.lostAfterUpdate, setup: true))
        #expect(!hintsPermission(.granted))
        #expect(!hintsPermission(.notRequested))
        #expect(!hintsPermission(.denied))
    }

    /// Someone who ignores screenshots is not greeted by the guide at every login; the next
    /// update that loses the grant hints again.
    @Test func permissionLostHintOncePerBuild() {
        #expect(!hintsPermission(.lostAfterUpdate, hinted: "31", build: "31"))
        #expect(hintsPermission(.lostAfterUpdate, hinted: "30", build: "31"))
    }

    /// With ad-hoc signing every update can silently drop Accessibility, so the hint returns
    /// once per build, not once ever.
    @Test func accessibilityHintOncePerBuild() {
        #expect(hintsAccessibility(trusted: false, hinted: nil, build: "30"))
        #expect(!hintsAccessibility(trusted: false, hinted: "30", build: "30"))
        #expect(hintsAccessibility(trusted: false, hinted: "30", build: "31"))
        #expect(!hintsAccessibility(trusted: true, hinted: nil, build: "31"))
    }
}

/// The setup assistant counts as seen when its window is closed (Done, Later, close button),
/// not when it is shown: its first step asks to restart Bufr, and quitting doesn't close windows.
@MainActor
struct SingleWindowPresenterTests {
    @Test func closingTheWindowIsReportedOnce() throws {
        var presented: [NSWindow] = []
        var closes = 0
        var close: (() -> Void)?
        let presenter = SingleWindowPresenter { presented.append($0) }

        presenter.show(title: "Setup", onClose: { closes += 1 }) { closeAction in
            close = closeAction
            return Text("Setup")
        }
        #expect(presented.count == 1)
        #expect(closes == 0)

        let closeWindow = try #require(close)
        closeWindow()
        #expect(closes == 1)
    }

    @Test func setupIsMarkedSeenOnlyWhenItsWindowCloses() throws {
        let defaults = try #require(UserDefaults(suiteName: "com.bufr.tests.setupSeen"))
        defaults.removePersistentDomain(forName: "com.bufr.tests.setupSeen")
        let controller = ScreenshotSetupWindowController(presenter: SingleWindowPresenter { _ in }, defaults: defaults, version: "3.0.0", makeView: { close in AnyView(Button("Done", action: close)) })

        controller.show()
        #expect(defaults.string(forKey: LaunchNotices.setupVersionKey) == nil)

        controller.close()
        #expect(defaults.string(forKey: LaunchNotices.setupVersionKey) == "3.0.0")
    }
}
