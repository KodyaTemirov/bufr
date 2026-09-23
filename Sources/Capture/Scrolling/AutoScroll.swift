import AppKit
import ApplicationServices
import CoreGraphics

/// When "Auto" scrolls on and when it has reached the end of the page.
struct AutoScrollPolicy {
    enum Decision: Equatable {
        case scrollAgain
        case reachedEnd
        case stop
    }

    /// Scroll distance per step, in points
    private(set) var stepPoints: CGFloat
    private let minimumStep: CGFloat
    private var stillSteps = 0

    /// Half the region per step leaves a wide overlap between frames.
    init(regionHeightPoints: CGFloat) {
        stepPoints = regionHeightPoints / 2
        minimumStep = regionHeightPoints / 8
    }

    mutating func record(_ step: ScrollStitcher.Step) -> Decision {
        switch step {
        case .added:
            stillSteps = 0
            return .scrollAgain
        case .noMovement:
            stillSteps += 1
            return stillSteps >= 3 ? .reachedEnd : .scrollAgain
        case .lostTrack:
            // The app scrolled further than asked (acceleration): smaller steps from now on
            stepPoints = max(minimumStep, stepPoints / 2)
            return .scrollAgain
        case .movedUp:
            return .scrollAgain
        case .limitReached:
            return .stop
        }
    }
}

/// Sends scroll-wheel events into the captured region.
@MainActor
protocol AutoScrolling: AnyObject {
    /// Posting events needs Accessibility
    var isAvailable: Bool { get }
    /// `point` is the region's centre in CG global coordinates (top-left origin)
    func scroll(by points: CGFloat, at point: CGPoint)
}

@MainActor
final class SystemAutoScroller: AutoScrolling {
    private var pointerPlaced = false

    var isAvailable: Bool { AXIsProcessTrusted() }

    func scroll(by points: CGFloat, at point: CGPoint) {
        // Scroll events go to whatever is under the pointer
        if !pointerPlaced {
            CGWarpMouseCursorPosition(point)
            pointerPlaced = true
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: -Int32(points.rounded()), wheel2: 0, wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
