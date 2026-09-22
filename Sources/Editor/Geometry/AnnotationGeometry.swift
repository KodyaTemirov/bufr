import AppKit
import CoreGraphics

/// Pure geometry for annotations: hit testing, handles, resizing and paths.
/// Everything is in base-image pixels with a top-left origin.
enum AnnotationGeometry {
    enum Handle: Hashable {
        case rect(SelectionGeometry.Handle)
        case start
        case end
    }

    // MARK: - Moving

    static func moved(_ shape: AnnotationShape, by delta: CGSize) -> AnnotationShape {
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.width, y: point.y + delta.height) }
        func shift(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.width, dy: delta.height) }

        switch shape {
        case let .arrow(start, end): return .arrow(start: shift(start), end: shift(end))
        case let .line(start, end): return .line(start: shift(start), end: shift(end))
        case let .rectangle(rect): return .rectangle(shift(rect))
        case let .filledRectangle(rect): return .filledRectangle(shift(rect))
        case let .ellipse(rect): return .ellipse(shift(rect))
        case let .text(origin, string): return .text(origin: shift(origin), string: string)
        case let .highlighter(rect): return .highlighter(shift(rect))
        case let .pencil(points): return .pencil(points.map(shift))
        case let .counter(center, number): return .counter(center: shift(center), number: number)
        case let .pixelate(rect): return .pixelate(shift(rect))
        case let .blur(rect): return .blur(shift(rect))
        case let .spotlight(rect): return .spotlight(shift(rect))
        }
    }

    // MARK: - Rect-like shapes

    /// The rect of shapes that are resized with eight handles.
    static func rect(of shape: AnnotationShape) -> CGRect? {
        switch shape {
        case let .rectangle(rect), let .filledRectangle(rect), let .ellipse(rect),
             let .highlighter(rect), let .pixelate(rect), let .blur(rect), let .spotlight(rect):
            return rect
        default:
            return nil
        }
    }

    static func replacingRect(of shape: AnnotationShape, with rect: CGRect) -> AnnotationShape {
        switch shape {
        case .rectangle: .rectangle(rect)
        case .filledRectangle: .filledRectangle(rect)
        case .ellipse: .ellipse(rect)
        case .highlighter: .highlighter(rect)
        case .pixelate: .pixelate(rect)
        case .blur: .blur(rect)
        case .spotlight: .spotlight(rect)
        default: shape
        }
    }

    // MARK: - Handles

    static func handles(for shape: AnnotationShape) -> [(handle: Handle, point: CGPoint)] {
        switch shape {
        case let .arrow(start, end), let .line(start, end):
            return [(.start, start), (.end, end)]
        default:
            guard let rect = rect(of: shape) else { return [] }
            return SelectionGeometry.Handle.allCases.map { (.rect($0), $0.point(in: rect)) }
        }
    }

    static func resized(_ shape: AnnotationShape, handle: Handle, to point: CGPoint, minimumSize: CGFloat) -> AnnotationShape {
        switch (shape, handle) {
        case let (.arrow(start, _), .end): return .arrow(start: start, end: point)
        case let (.arrow(_, end), .start): return .arrow(start: point, end: end)
        case let (.line(start, _), .end): return .line(start: start, end: point)
        case let (.line(_, end), .start): return .line(start: point, end: end)
        case let (_, .rect(rectHandle)):
            guard let rect = rect(of: shape) else { return shape }
            let unbounded = CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
            let resized = SelectionGeometry.resized(rect, handle: rectHandle, to: point, bounds: unbounded, minimumSize: minimumSize)
            return replacingRect(of: shape, with: resized)
        default:
            return shape
        }
    }

    // MARK: - Hit testing

    static func hitTest(_ annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + annotation.style.lineWidth / 2
        switch annotation.shape {
        case let .arrow(start, end), let .line(start, end):
            return distance(from: point, toSegment: start, end) <= reach
        case let .rectangle(rect):
            return rect.insetBy(dx: -reach, dy: -reach).contains(point)
                && !rect.insetBy(dx: reach, dy: reach).contains(point)
        case let .ellipse(rect):
            return isInsideEllipse(point, rect.insetBy(dx: -reach, dy: -reach))
                && !isInsideEllipse(point, rect.insetBy(dx: reach, dy: reach))
        case let .filledRectangle(rect), let .highlighter(rect), let .pixelate(rect), let .blur(rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .spotlight(rect):
            // The bright hole is what the user sees; its edge selects it
            return rect.insetBy(dx: -reach, dy: -reach).contains(point)
        case .text:
            return bounds(of: annotation).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .pencil(points):
            guard points.count > 1 else { return points.first.map { hypot($0.x - point.x, $0.y - point.y) <= reach } ?? false }
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
        case let .counter(center, _):
            return hypot(point.x - center.x, point.y - center.y) <= counterRadius(annotation.style) + tolerance
        }
    }

    static func bounds(of annotation: Annotation) -> CGRect {
        let pad = annotation.style.lineWidth / 2 + 1
        switch annotation.shape {
        case let .arrow(start, end):
            return arrowPath(from: start, to: end, width: annotation.style.lineWidth).boundingBox.insetBy(dx: -1, dy: -1)
        case let .line(start, end):
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                .insetBy(dx: -pad, dy: -pad)
        case let .rectangle(rect), let .ellipse(rect):
            return rect.insetBy(dx: -pad, dy: -pad)
        case let .filledRectangle(rect), let .highlighter(rect), let .pixelate(rect), let .blur(rect), let .spotlight(rect):
            return rect
        case let .text(origin, string):
            return CGRect(origin: origin, size: textSize(string, style: annotation.style))
        case let .pencil(points):
            guard let first = points.first else { return .null }
            let rect = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            return rect.insetBy(dx: -pad, dy: -pad)
        case let .counter(center, _):
            let radius = counterRadius(annotation.style)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    // MARK: - Shapes

    /// A filled arrow: tapered shaft plus a head proportional to the stroke width.
    static func arrowPath(from start: CGPoint, to end: CGPoint, width: CGFloat) -> CGPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let path = CGMutablePath()
        guard length > 0.5 else { return path }

        let headLength = min(length * 0.5, max(width * 4.5, 12))
        let headHalfWidth = headLength * 0.45
        let shaftEnd = length - headLength
        let tailHalf = max(width * 0.2, 0.5)
        let shaftHalf = width / 2

        path.addLines(between: [
            CGPoint(x: 0, y: tailHalf),
            CGPoint(x: shaftEnd, y: shaftHalf),
            CGPoint(x: shaftEnd, y: headHalfWidth),
            CGPoint(x: length, y: 0),
            CGPoint(x: shaftEnd, y: -headHalfWidth),
            CGPoint(x: shaftEnd, y: -shaftHalf),
            CGPoint(x: 0, y: -tailHalf),
        ])
        path.closeSubpath()

        var transform = CGAffineTransform(translationX: start.x, y: start.y).rotated(by: atan2(dy, dx))
        return path.copy(using: &transform) ?? path
    }

    /// Freehand stroke smoothed with quadratic curves through segment midpoints.
    static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// ⇧ while drawing a line or arrow: the angle snaps to 45° steps and the end is the pointer
    /// projected onto that direction (a horizontal line ends right under the pointer).
    static func snappedEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let projected = dx * direction.x + dy * direction.y
        return CGPoint(x: start.x + projected * direction.x, y: start.y + projected * direction.y)
    }

    // MARK: - Text and counters

    static func textFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
        return rounded ?? base
    }

    static func textSize(_ string: String, style: AnnotationStyle) -> CGSize {
        let text = string.isEmpty ? " " : string
        let rect = NSAttributedString(string: text, attributes: [.font: textFont(size: style.fontSize)])
            .boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(rect.width) + 4, height: ceil(rect.height))
    }

    static func counterRadius(_ style: AnnotationStyle) -> CGFloat {
        style.fontSize * 0.75
    }

    // MARK: - Helpers

    private static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    private static func isInsideEllipse(_ point: CGPoint, _ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let nx = (point.x - rect.midX) / (rect.width / 2)
        let ny = (point.y - rect.midY) / (rect.height / 2)
        return nx * nx + ny * ny <= 1
    }
}

extension AnnotationDocument {
    /// The annotation drawn on top at `point`.
    func topmost(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { AnnotationGeometry.hitTest($0, at: point, tolerance: tolerance) }
    }
}
