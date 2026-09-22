import CoreGraphics

/// Conversions between the coordinate systems a capture touches.
///
/// - Cocoa global: origin at the bottom-left of the primary display, y up
///   (`NSScreen.frame`, `NSEvent.mouseLocation`, window frames).
/// - CG global: origin at the top-left of the primary display, y down
///   (`CGDisplayBounds`, `SCWindow.frame`, `kCGWindowBounds`).
/// - Display-local: points inside one display, origin at its top-left (selection rects).
///
/// `primaryHeight` is `NSScreen.screens[0].frame.height` — never `NSScreen.main`, which is
/// the screen of the key window.
enum ScreenGeometry {
    static func cgRect(fromCocoa rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The same formula: flipping twice is the identity.
    static func cocoaRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        cgRect(fromCocoa: rect, primaryHeight: primaryHeight)
    }

    static func cgPoint(fromCocoa point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Bottom-left-origin rect inside a box of `height` → top-left-origin rect (and back).
    static func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func flipped(_ point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }

    /// Display-local rect in points (top-left origin) → pixel rect in an image of that display.
    /// Edges round outward so the selection is never cut; the result is clamped to the image
    /// and is `.null` when nothing of the rect lies inside it.
    static func pixelRect(forLocal rect: CGRect, displayPointSize: CGSize, imagePixelSize: CGSize) -> CGRect {
        let scaleX = imagePixelSize.width / displayPointSize.width
        let scaleY = imagePixelSize.height / displayPointSize.height
        // The tolerance keeps float noise (100.5 × 2 = 201.0000001) from adding a pixel
        let tolerance: CGFloat = 0.001
        let minX = (rect.minX * scaleX + tolerance).rounded(.down)
        let minY = (rect.minY * scaleY + tolerance).rounded(.down)
        let maxX = (rect.maxX * scaleX - tolerance).rounded(.up)
        let maxY = (rect.maxY * scaleY - tolerance).rounded(.up)
        let pixels = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let clamped = pixels.intersection(CGRect(origin: .zero, size: imagePixelSize))
        return clamped.isEmpty ? .null : clamped
    }
}
