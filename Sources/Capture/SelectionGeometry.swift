import CoreGraphics

/// Pure math for drawing and moving a selection rectangle.
enum SelectionGeometry {
    /// Rect spanned by a drag from `start` to `current`, clamped to `bounds`.
    /// `square` (⇧) uses the longer side; `fromCenter` (⌥) grows the rect around `start`.
    static func rect(from start: CGPoint, to current: CGPoint, square: Bool, fromCenter: Bool, bounds: CGRect) -> CGRect {
        var dx = current.x - start.x
        var dy = current.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }

        let rect: CGRect
        if fromCenter {
            rect = CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        } else {
            rect = CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
        }

        let clamped = rect.intersection(bounds)
        return clamped.isNull ? CGRect(origin: start, size: .zero) : clamped
    }

    /// `rect` shifted by `delta`, kept entirely inside `bounds` (Space-drag moves the selection).
    static func moved(_ rect: CGRect, by delta: CGSize, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.width, dy: delta.height)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }
}
