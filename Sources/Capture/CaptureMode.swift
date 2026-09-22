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
