import CoreGraphics

enum CaptureMode: Sendable, Equatable {
    case area
    case window
    case fullscreen
    case previousArea
    /// ⌘⇧5: editable selection plus a mode bar
    case allInOne
    /// ⌘⇧2: select an area, copy the text in it
    case text
    /// ⌥⇧⌘4: select an area, then record it while it scrolls into one long image
    case scrolling
}

/// A display-local rectangle, remembered for "Capture Previous Area".
struct CaptureRegion: Codable, Equatable, Sendable {
    /// Stable across reboots and reconnects, unlike CGDirectDisplayID
    var displayUUID: String
    /// Points, top-left origin of that display
    var localRect: CGRect
}

/// What the user picked on the overlay.
enum CaptureSelection: Equatable {
    case area(displayID: CGDirectDisplayID, localRect: CGRect)
    case window(CapturableWindow)
    /// The whole display (all-in-one "Screen"); not remembered as the previous area
    case display(CGDirectDisplayID)
    /// All-in-one "Scrolling": record this area while it scrolls
    case scroll(displayID: CGDirectDisplayID, localRect: CGRect)
}

/// What a capture session ends with: an image, or the area a scrolling capture records.
enum CaptureSessionResult {
    case image(CaptureOutcome)
    case scrollRegion(ScrollRegion)
}

/// The area a scrolling capture records, on one display.
struct ScrollRegion: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// Points, top-left origin of that display
    let localRect: CGRect
    /// The display's frame (Cocoa global)
    let screenFrame: CGRect
    /// Pixels per point of that display
    let pointScale: CGFloat
    let sourceAppId: String?
    let sourceAppName: String?

    var pixelSize: CGSize {
        CGSize(width: (localRect.width * pointScale).rounded(), height: (localRect.height * pointScale).rounded())
    }

    /// Where the region is on screen (Cocoa global)
    var cocoaRect: CGRect {
        ScreenGeometry.cocoaRect(fromLocal: localRect, screenFrame: screenFrame)
    }

    /// A window (CG global) as a region of the screen it is on, cut to that screen.
    static func localRect(ofWindow cgFrame: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect? {
        let screen = ScreenGeometry.cgRect(fromCocoa: screenFrame, primaryHeight: primaryHeight)
        let visible = cgFrame.intersection(screen)
        guard !visible.isNull, !visible.isEmpty else { return nil }
        return visible.offsetBy(dx: -screen.minX, dy: -screen.minY)
    }
}

struct CaptureOutcome: Sendable {
    let image: CGImage
    /// Pixels per point of the captured content (2 on Retina)
    let pointScale: CGFloat
    let sourceAppId: String?
    let sourceAppName: String?
    /// Set for area captures; saved as the previous area
    let region: CaptureRegion?
    /// Where the captured content was on screen (Cocoa global); pins open exactly there
    let screenRect: CGRect?
}
