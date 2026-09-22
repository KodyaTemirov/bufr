import Testing
@testable import Bufr

struct LaunchNoticesTests {
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
        #expect(LaunchNotices.shouldHintPermissionLost(.lostAfterUpdate, showingSetup: false))
        #expect(!LaunchNotices.shouldHintPermissionLost(.lostAfterUpdate, showingSetup: true))
        #expect(!LaunchNotices.shouldHintPermissionLost(.granted, showingSetup: false))
        #expect(!LaunchNotices.shouldHintPermissionLost(.notRequested, showingSetup: false))
        #expect(!LaunchNotices.shouldHintPermissionLost(.denied, showingSetup: false))
    }
}
