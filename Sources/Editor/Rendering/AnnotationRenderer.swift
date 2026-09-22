import AppKit
import CoreGraphics

/// The one renderer for both the editor canvas and export, so what you see is what you save.
///
/// Contexts passed in must use base-image pixels with a top-left origin (y down).
/// Pass order: base → effects (from base pixels) → spotlight dimming → vector annotations.
enum AnnotationRenderer {
    static func draw(
        _ document: AnnotationDocument,
        base: CGImage,
        in context: CGContext,
        includeBase: Bool = true,
        effects: EffectRenderer = .shared,
        effectPatch: ((Annotation) -> (image: CGImage, rect: CGRect)?)? = nil
    ) {
        let imageRect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        if includeBase {
            context.drawImageTopLeft(base, in: imageRect)
        }

        for annotation in document.annotations {
            switch annotation.shape {
            case .pixelate, .blur:
                if let patch = effectPatch?(annotation) ?? effects.patch(for: annotation.shape, base: base) {
                    context.drawImageTopLeft(patch.image, in: patch.rect)
                }
            default:
                break
            }
        }

        let spotlights = document.annotations.compactMap { annotation -> CGRect? in
            if case let .spotlight(rect) = annotation.shape { return rect.standardized }
            return nil
        }
        if !spotlights.isEmpty {
            let path = CGMutablePath()
            path.addRect(imageRect)
            spotlights.forEach { path.addRoundedRect(in: $0, cornerWidth: 8, cornerHeight: 8) }
            context.saveGState()
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 0.5))
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }

        for annotation in document.annotations {
            drawVector(annotation, in: context)
        }
    }

    /// Flattened result: the crop (or the whole image) with everything drawn in.
    static func renderFlattened(_ document: AnnotationDocument, base: CGImage) -> CGImage? {
        let size = document.outputSize
        let crop = document.crop?.standardized ?? CGRect(origin: .zero, size: size)
        let colorSpace = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: max(1, Int(size.width)), height: max(1, Int(size.height)),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Top-left user space in base-image pixels, shifted so the crop's corner is at 0,0
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        draw(document, base: base, in: context)
        return context.makeImage()
    }

    // MARK: - Vector shapes

    static func drawVector(_ annotation: Annotation, in context: CGContext) {
        let style = annotation.style
        let color = style.color.cgColor
        context.saveGState()
        defer { context.restoreGState() }

        switch annotation.shape {
        case let .arrow(start, end):
            context.addPath(AnnotationGeometry.arrowPath(from: start, to: end, width: style.lineWidth))
            context.setFillColor(color)
            context.fillPath()

        case let .line(start, end):
            context.setStrokeColor(color)
            context.setLineWidth(style.lineWidth)
            context.setLineCap(.round)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

        case let .rectangle(rect):
            let corner = min(style.lineWidth, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect.standardized, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.setStrokeColor(color)
            context.setLineWidth(style.lineWidth)
            context.strokePath()

        case let .filledRectangle(rect):
            context.setFillColor(color)
            context.fill(rect.standardized)

        case let .ellipse(rect):
            context.setStrokeColor(color)
            context.setLineWidth(style.lineWidth)
            context.strokeEllipse(in: rect.standardized)

        case let .text(origin, string):
            drawText(string, at: origin, style: style, in: context)

        case let .highlighter(rect):
            context.setBlendMode(.multiply)
            context.setFillColor(style.color.cgColor.copy(alpha: 0.4) ?? color)
            context.fill(rect.standardized)

        case let .pencil(points):
            context.addPath(AnnotationGeometry.smoothedPath(points))
            context.setStrokeColor(color)
            context.setLineWidth(style.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()

        case let .counter(center, number):
            let radius = AnnotationGeometry.counterRadius(style)
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: AnnotationGeometry.textFont(size: radius * 1.1),
                .foregroundColor: isLight(style.color) ? NSColor.black : NSColor.white,
            ])
            let size = label.size()
            withAppKitContext(context) {
                label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
            }

        case .pixelate, .blur, .spotlight:
            break // drawn in the earlier passes
        }
    }

    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let fill = NSColor(cgColor: style.color.cgColor) ?? .red
        let outline = isLight(style.color) ? NSColor.black : NSColor.white
        let text = NSAttributedString(string: string, attributes: [
            .font: AnnotationGeometry.textFont(size: style.fontSize),
            .foregroundColor: fill,
            .strokeColor: outline,
            .strokeWidth: -3, // negative: fill and outline
        ])
        withAppKitContext(context) {
            text.draw(with: CGRect(origin: origin, size: CGSize(width: 100_000, height: 100_000)), options: [.usesLineFragmentOrigin])
        }
    }

    /// AppKit text drawing into our top-left CG context.
    private static func withAppKitContext(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func isLight(_ color: RGBAColor) -> Bool {
        0.299 * color.red + 0.587 * color.green + 0.114 * color.blue > 0.7
    }
}
