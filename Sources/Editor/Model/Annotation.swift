import CoreGraphics
import Foundation

struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let red = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    static let orange = RGBAColor(red: 1, green: 0.58, blue: 0)
    static let yellow = RGBAColor(red: 1, green: 0.84, blue: 0.04)
    static let green = RGBAColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let purple = RGBAColor(red: 0.69, green: 0.32, blue: 0.87)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)

    static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

/// Sizes are in base-image pixels (points × the image's point scale).
struct AnnotationStyle: Codable, Hashable, Sendable {
    var color: RGBAColor
    var lineWidth: Double
    var fontSize: Double
}

/// Geometry in base-image pixels with a top-left origin, independent of zoom.
enum AnnotationShape: Codable, Hashable, Sendable {
    case arrow(start: CGPoint, end: CGPoint)
    case line(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case filledRectangle(CGRect)
    case ellipse(CGRect)
    case text(origin: CGPoint, string: String)
    /// Translucent marker over text rows
    case highlighter(CGRect)
    case pencil([CGPoint])
    /// Numbered step marker
    case counter(center: CGPoint, number: Int)
    case pixelate(CGRect)
    case blur(CGRect)
    /// Everything outside the rect is dimmed
    case spotlight(CGRect)
}

struct Annotation: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var shape: AnnotationShape
    var style: AnnotationStyle
}

/// The editable layers of one image: stored as `<uuid>.annotations.json` next to the
/// untouched original `<uuid>_orig.png`.
struct AnnotationDocument: Codable, Hashable, Sendable {
    var version = 1
    var baseImageFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    /// Pixels per point of the original (2 on Retina); new strokes and text scale with it
    var pointScale: Double
    /// Base-image pixels; nil = whole image
    var crop: CGRect?
    var annotations: [Annotation] = []

    var outputSize: CGSize {
        pixelCrop?.size ?? CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// The crop on whole pixels inside the image: a crop edge between pixels would resample
    /// (blur) the whole result.
    var pixelCrop: CGRect? {
        guard let crop else { return nil }
        let clipped = crop.standardized.integral.intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.shape { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    mutating func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    mutating func remove(ids: Set<UUID>) {
        annotations.removeAll { ids.contains($0.id) }
    }

    /// Copies shifted by `offset` pixels, added on top; returns the new ids.
    mutating func duplicate(ids: Set<UUID>, offset: CGFloat) -> [UUID] {
        let copies = annotations.filter { ids.contains($0.id) }.map { original in
            Annotation(shape: AnnotationGeometry.moved(original.shape, by: CGSize(width: offset, height: offset)), style: original.style)
        }
        annotations.append(contentsOf: copies)
        return copies.map(\.id)
    }
}
