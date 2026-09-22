import CoreGraphics

enum ScreenPinGeometry {
    /// A pin never starts larger than this share of the screen's visible area
    static let maxScreenFraction: CGFloat = 0.8
    static let minimumOpacity: CGFloat = 0.2

    /// Starting frame (Cocoa global): where the content was captured when known, otherwise
    /// centred on the mouse. Large images are scaled down keeping their aspect ratio, and the
    /// frame is kept inside the visible area.
    static func initialFrame(imageSize: CGSize, sourceRect: CGRect?, mouse: CGPoint, visibleFrame: CGRect) -> CGRect {
        let limit = CGSize(width: visibleFrame.width * maxScreenFraction, height: visibleFrame.height * maxScreenFraction)
        let size = fitted(imageSize, within: limit)

        let frame: CGRect
        if let sourceRect, sourceRect.size == size {
            frame = sourceRect
        } else {
            let center = sourceRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? mouse
            frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }
        return clamped(frame, to: visibleFrame)
    }

    /// `size` scaled down (never up) to fit `limit`, keeping the aspect ratio.
    static func fitted(_ size: CGSize, within limit: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let scale = min(1, limit.width / size.width, limit.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Moves `rect` inside `bounds` (it already fits).
    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return result
    }

    /// Two-finger scroll up makes the pin more opaque, down more transparent.
    static func opacity(_ current: CGFloat, scrollDelta: CGFloat) -> CGFloat {
        min(1, max(minimumOpacity, current + scrollDelta * 0.01))
    }
}
