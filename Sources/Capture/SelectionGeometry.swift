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

    // MARK: - Handles (all-in-one mode)

    /// Resize handles, named by the rect edges they move (orientation-neutral).
    enum Handle: CaseIterable {
        case minXMinY, midXMinY, maxXMinY, maxXMidY, maxXMaxY, midXMaxY, minXMaxY, minXMidY

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .minXMinY: CGPoint(x: rect.minX, y: rect.minY)
            case .midXMinY: CGPoint(x: rect.midX, y: rect.minY)
            case .maxXMinY: CGPoint(x: rect.maxX, y: rect.minY)
            case .maxXMidY: CGPoint(x: rect.maxX, y: rect.midY)
            case .maxXMaxY: CGPoint(x: rect.maxX, y: rect.maxY)
            case .midXMaxY: CGPoint(x: rect.midX, y: rect.maxY)
            case .minXMaxY: CGPoint(x: rect.minX, y: rect.maxY)
            case .minXMidY: CGPoint(x: rect.minX, y: rect.midY)
            }
        }

        var movesMinX: Bool { [.minXMinY, .minXMidY, .minXMaxY].contains(self) }
        var movesMaxX: Bool { [.maxXMinY, .maxXMidY, .maxXMaxY].contains(self) }
        var movesMinY: Bool { [.minXMinY, .midXMinY, .maxXMinY].contains(self) }
        var movesMaxY: Bool { [.minXMaxY, .midXMaxY, .maxXMaxY].contains(self) }
    }

    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> Handle? {
        Handle.allCases.first { handle in
            let center = handle.point(in: rect)
            return abs(center.x - point.x) <= tolerance && abs(center.y - point.y) <= tolerance
        }
    }

    /// Moves the edges `handle` controls to `point`. Edges stop at `minimumSize` instead of
    /// crossing the opposite side, and stay inside `bounds`.
    static func resized(_ rect: CGRect, handle: Handle, to point: CGPoint, bounds: CGRect, minimumSize: CGFloat) -> CGRect {
        let x = min(max(point.x, bounds.minX), bounds.maxX)
        let y = min(max(point.y, bounds.minY), bounds.maxY)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(x, maxX - minimumSize) }
        if handle.movesMaxX { maxX = max(x, minX + minimumSize) }
        if handle.movesMinY { minY = min(y, maxY - minimumSize) }
        if handle.movesMaxY { maxY = max(y, minY + minimumSize) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Arrow-key move.
    static func nudged(_ rect: CGRect, dx: CGFloat, dy: CGFloat, bounds: CGRect) -> CGRect {
        moved(rect, by: CGSize(width: dx, height: dy), within: bounds)
    }

    /// ⌥+arrow resize: the right edge follows `dWidth`, the visual bottom edge (minY here)
    /// follows `dHeight`; the top-left corner stays put.
    static func grown(_ rect: CGRect, dWidth: CGFloat, dHeight: CGFloat, bounds: CGRect, minimumSize: CGFloat) -> CGRect {
        let width = min(max(rect.width + dWidth, minimumSize), bounds.maxX - rect.minX)
        let height = min(max(rect.height + dHeight, minimumSize), rect.maxY - bounds.minY)
        return CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
    }
}
