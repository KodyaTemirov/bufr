import CoreGraphics

/// An on-screen window that window mode can highlight and capture.
struct CapturableWindow: Equatable, Sendable {
    let windowID: CGWindowID
    /// CG global points (top-left origin)
    let frame: CGRect
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
}
