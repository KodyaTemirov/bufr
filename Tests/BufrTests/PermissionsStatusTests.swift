import Foundation
import Testing
@testable import Bufr

struct PermissionsStatusTests {
    @Test func grantedWinsOverEverything() {
        #expect(PermissionsManager.status(granted: true, requestedBefore: true, grantedIdentity: "old", currentIdentity: "new") == .granted)
    }

    @Test func neverAskedIsNotRequested() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: false, grantedIdentity: nil, currentIdentity: "new") == .notRequested)
    }

    @Test func askedAndRefusedIsDenied() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedIdentity: nil, currentIdentity: "new") == .denied)
        // Revoked by the user for this very binary
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedIdentity: "new", currentIdentity: "new") == .denied)
    }

    /// Ad-hoc signed builds get a new code identity; macOS no longer honours the old grant.
    @Test func grantForAnotherBinaryIsLostAfterUpdate() {
        #expect(PermissionsManager.status(granted: false, requestedBefore: true, grantedIdentity: "old", currentIdentity: "new") == .lostAfterUpdate)
    }
}

/// The grant is remembered per binary, not per CFBundleVersion: a rebuild or an update that
/// kept the version number also loses an ad-hoc grant while System Settings still shows it ON.
@MainActor
@Suite(.serialized)
struct PermissionsIdentityTests {
    static let suiteName = "com.bufr.tests.permissions"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test func rebuildWithTheSameVersionIsLostNotDenied() {
        defaults.set(true, forKey: "screenCaptureRequested")
        defaults.set("old-binary", forKey: "screenCaptureGrantedIdentity")

        let permissions = PermissionsManager(defaults: defaults, codeIdentity: "new-binary", preflight: { false })

        #expect(permissions.screenCapture == .lostAfterUpdate)
    }

    /// Bufr 3.0 builds before this fix stored the build number; same version must still count
    /// as lost, since macOS refuses the grant.
    @Test func grantRecordedByBuildNumberCountsAsLost() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        defaults.set(true, forKey: "screenCaptureRequested")
        defaults.set(build, forKey: "screenCaptureGrantedBuild")

        let permissions = PermissionsManager(defaults: defaults, codeIdentity: "new-binary", preflight: { false })

        #expect(permissions.screenCapture == .lostAfterUpdate)
    }

    @Test func grantRemembersTheCurrentBinary() {
        let permissions = PermissionsManager(defaults: defaults, codeIdentity: "this-binary", preflight: { true })

        #expect(permissions.screenCapture == .granted)
        #expect(defaults.string(forKey: "screenCaptureGrantedIdentity") == "this-binary")
    }

    @Test func codeIdentityIsTheRunningBinarysHash() throws {
        let identity = try #require(CodeIdentity.current)

        let isHex = identity.allSatisfy { $0.isHexDigit }
        #expect(identity.count == 40)
        #expect(isHex)
    }
}
