import CoreGraphics

enum WindowPicker {
    /// The frontmost window containing `point` (CG global); `windows` must be front-to-back.
    static func window(at point: CGPoint, in windows: [CapturableWindow]) -> CapturableWindow? {
        windows.first { $0.frame.contains(point) }
    }
}
