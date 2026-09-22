import CoreGraphics
import CoreImage

/// Pixelate and blur patches, always computed from the base image's own pixels.
final class EffectRenderer: Sendable {
    static let shared = EffectRenderer()

    private let context = CIContext(options: [.cacheIntermediates: false])

    /// The effected copy of `shape`'s rect (base pixels, top-left origin) and where to draw it;
    /// nil for shapes that are not effects or lie outside the image.
    func patch(for shape: AnnotationShape, base: CGImage) -> (image: CGImage, rect: CGRect)? {
        let imageBounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let rect: CGRect
        let isPixelate: Bool
        switch shape {
        case let .pixelate(r): rect = r; isPixelate = true
        case let .blur(r): rect = r; isPixelate = false
        default: return nil
        }
        let clipped = rect.standardized.intersection(imageBounds).integral
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }

        // Core Image works bottom-left
        let ciRect = CGRect(x: clipped.minX, y: imageBounds.height - clipped.maxY, width: clipped.width, height: clipped.height)
        let input = CIImage(cgImage: base).clampedToExtent()
        let output: CIImage
        if isPixelate {
            // Blocks sized to the region, aligned to its corner; each block is one flat color
            let block = max(8, (max(clipped.width, clipped.height) / 12).rounded())
            output = input.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: block,
                kCIInputCenterKey: CIVector(cgPoint: ciRect.origin),
            ])
        } else {
            output = input.applyingGaussianBlur(sigma: max(6, min(clipped.width, clipped.height) / 8))
        }

        guard let image = context.createCGImage(output.cropped(to: ciRect), from: ciRect) else { return nil }
        return (image, clipped)
    }
}
