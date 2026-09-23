import CoreGraphics
import Testing
@testable import Bufr

struct AutoScrollPolicyTests {
    @Test func stepIsHalfTheRegion() {
        #expect(AutoScrollPolicy(regionHeightPoints: 400).stepPoints == 200)
    }

    @Test func threeStillStepsMeanTheEnd() {
        var policy = AutoScrollPolicy(regionHeightPoints: 400)

        #expect(policy.record(.noMovement) == .scrollAgain)
        #expect(policy.record(.noMovement) == .scrollAgain)
        #expect(policy.record(.noMovement) == .reachedEnd)
    }

    @Test func movementResetsTheCount() {
        var policy = AutoScrollPolicy(regionHeightPoints: 400)
        _ = policy.record(.noMovement)
        _ = policy.record(.noMovement)

        #expect(policy.record(.added(120)) == .scrollAgain)
        #expect(policy.record(.noMovement) == .scrollAgain)
        #expect(policy.record(.noMovement) == .scrollAgain)
    }

    /// The page jumped further than the frames overlap: smaller steps, but never tiny ones.
    @Test func lostTrackHalvesTheStepDownToAnEighth() {
        var policy = AutoScrollPolicy(regionHeightPoints: 400)

        #expect(policy.record(.lostTrack) == .scrollAgain)
        #expect(policy.stepPoints == 100)
        _ = policy.record(.lostTrack)
        _ = policy.record(.lostTrack)
        #expect(policy.stepPoints == 50)
    }

    @Test func limitStops() {
        var policy = AutoScrollPolicy(regionHeightPoints: 400)

        #expect(policy.record(.limitReached) == .stop)
        #expect(policy.record(.movedUp) == .scrollAgain)
    }
}
