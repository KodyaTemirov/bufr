import CoreGraphics

enum AnnotationGeometry {
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
}
