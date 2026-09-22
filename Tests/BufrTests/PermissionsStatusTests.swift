import Testing
@testable import Bufr

struct PermissionsStatusTests {
    @Test func grantedWinsOverEverything() {
        #expect(PermissionsManager.status(granted: true, requestedBefore: true, grantedBuild: "21", currentBuild: "30") == .granted)
    }

    @Test func neverAskedIsNotRequested() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: false, grantedBuild: nil, currentBuild: "30") == .notRequested)
    }

    @Test func askedAndRefusedIsDenied() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedBuild: nil, currentBuild: "30") == .denied)
        // Revoked by the user on the same build
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedBuild: "30", currentBuild: "30") == .denied)
    }

    /// Ad-hoc signed updates get a new code identity; macOS no longer honours the old grant.
    @Test func grantFromOlderBuildIsLostAfterUpdate() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedBuild: "21", currentBuild: "30") == .lostAfterUpdate)
    }
}
