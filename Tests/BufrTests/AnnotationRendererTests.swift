import CoreGraphics
import Testing
@testable import Bufr

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] { TestImages.pixel(image, x, y) }

private func isRed(_ rgba: [UInt8]) -> Bool { rgba[0] > 200 && rgba[1] < 90 && rgba[2] < 90 }
private func isWhite(_ rgba: [UInt8]) -> Bool { rgba[0] > 245 && rgba[1] > 245 && rgba[2] > 245 }

/// Solid image; `topColor` fills the upper half when given.
private func base(width: Int = 100, height: Int = 60, topColor: CGColor? = nil) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let topColor {
        context.setFillColor(topColor)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2)) // CG origin is bottom-left
    }
    return context.makeImage()!
}

/// Horizontal gradient so neighbouring pixels differ.
private func gradient(width: Int = 100, height: Int = 60) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in 0..<width {
        context.setFillColor(CGColor(srgbRed: CGFloat(x) / CGFloat(width), green: 0.5, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return context.makeImage()!
}

struct AnnotationRendererTests {
    let red = AnnotationStyle(color: .red, lineWidth: 4, fontSize: 30)

    private func document(_ shapes: [AnnotationShape], width: Int = 100, height: Int = 60, crop: CGRect? = nil) -> AnnotationDocument {
        AnnotationDocument(
            baseImageFilename: "x", pixelWidth: width, pixelHeight: height, pointScale: 1, crop: crop,
            annotations: shapes.map { Annotation(shape: $0, style: red) }
        )
    }

    @Test func baseImageStaysUpright() throws {
        let output = try #require(AnnotationRenderer.renderFlattened(document([]), base: base(topColor: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))))

        #expect(isRed(pixel(output, 5, 5)))
        #expect(isWhite(pixel(output, 5, 55)))
    }

    @Test func topLeftStaysTopLeft() throws {
        let output = try #require(AnnotationRenderer.renderFlattened(document([.filledRectangle(CGRect(x: 0, y: 0, width: 20, height: 20))]), base: base()))

        #expect(isRed(pixel(output, 5, 5)))
        #expect(isWhite(pixel(output, 5, 55)))
        #expect(isWhite(pixel(output, 95, 5)))
    }

    @Test func cropDefinesOutputSize() throws {
        let doc = document([.filledRectangle(CGRect(x: 10, y: 10, width: 5, height: 5)), .filledRectangle(CGRect(x: 90, y: 50, width: 5, height: 5))],
                           crop: CGRect(x: 10, y: 10, width: 50, height: 40))

        let output = try #require(AnnotationRenderer.renderFlattened(doc, base: base()))

        #expect(output.width == 50 && output.height == 40)
        #expect(isRed(pixel(output, 1, 1)))
        #expect(isWhite(pixel(output, 45, 35))) // the second square lies outside the crop
    }

    @Test func pixelateProducesUniformBlocks() throws {
        let source = gradient()
        let output = try #require(AnnotationRenderer.renderFlattened(document([.pixelate(CGRect(x: 0, y: 0, width: 60, height: 60))]), base: source))

        #expect(pixel(output, 1, 1) == pixel(output, 4, 4))
        #expect(pixel(output, 1, 30) == pixel(output, 4, 30))
        #expect(pixel(source, 1, 1) != pixel(source, 4, 1)) // the source did differ there
        #expect(pixel(output, 80, 5) == pixel(source, 80, 5)) // outside is untouched
    }

    @Test func spotlightDimsEverythingElse() throws {
        let output = try #require(AnnotationRenderer.renderFlattened(document([.spotlight(CGRect(x: 20, y: 20, width: 20, height: 20))]), base: base()))

        #expect(isWhite(pixel(output, 30, 30)))
        #expect(pixel(output, 5, 5)[0] < 160)
    }

    @Test func textLeavesInkNearItsOrigin() throws {
        let output = try #require(AnnotationRenderer.renderFlattened(document([.text(origin: CGPoint(x: 5, y: 5), string: "W")]), base: base()))

        let ink = (5..<35).flatMap { y in (5..<35).map { x in pixel(output, x, y) } }.contains { !isWhite($0) }
        #expect(ink)
        #expect(isWhite(pixel(output, 90, 55)))
    }

    @Test func renderingIsDeterministic() throws {
        let doc = document([.arrow(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 80, y: 50)), .counter(center: CGPoint(x: 50, y: 30), number: 2)])
        let first = try #require(AnnotationRenderer.renderFlattened(doc, base: base()))
        let second = try #require(AnnotationRenderer.renderFlattened(doc, base: base()))

        #expect(ImageEncoder.pngData(from: first, pointScale: 1, downscaleToOneX: false) == ImageEncoder.pngData(from: second, pointScale: 1, downscaleToOneX: false))
    }

    /// The canvas draws annotations on a transparent layer over the base image; export draws
    /// them onto the base. A highlighter must look the same both ways (dark UI included).
    @Test func highlighterLooksTheSameOnCanvasAndInExport() throws {
        let dark = base(width: 100, height: 60, topColor: CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        var document = AnnotationDocument(baseImageFilename: "b", pixelWidth: 100, pixelHeight: 60, pointScale: 1)
        document.add(Annotation(shape: .highlighter(CGRect(x: 0, y: 0, width: 100, height: 60)), style: AnnotationStyle(color: .yellow, lineWidth: 4, fontSize: 20)))

        let exported = try #require(AnnotationRenderer.renderFlattened(document, base: dark))

        // Canvas: the overlay drawn alone, composited normally over the base
        let context = CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(dark, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let overlay = CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        overlay.translateBy(x: 0, y: 60)
        overlay.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(document, base: dark, in: overlay, includeBase: false)
        context.draw(overlay.makeImage()!, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let canvas = context.makeImage()!

        for (x, y) in [(50, 10), (50, 50)] {
            let a = pixel(exported, x, y), b = pixel(canvas, x, y)
            #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 3 }, "export \(a) vs canvas \(b) at \(x),\(y)")
        }
        #expect(pixel(exported, 50, 10)[0] > 90) // visibly yellow on the dark half
    }

    /// Crop edges between pixels must not resample the whole image.
    @Test func fractionalCropKeepsPixelsSharp() throws {
        let context = CGContext(
            data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for x in 0..<40 {
            let value: CGFloat = x.isMultiple(of: 2) ? 0 : 1
            context.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 10))
        }
        let stripes = context.makeImage()!
        var document = AnnotationDocument(baseImageFilename: "s", pixelWidth: 40, pixelHeight: 10, pointScale: 1)
        document.crop = CGRect(x: 10.5, y: 0.25, width: 20.3, height: 9.5)

        let output = try #require(AnnotationRenderer.renderFlattened(document, base: stripes))

        let row = (0..<output.width).map { pixel(output, $0, output.height / 2)[0] }
        #expect(row.allSatisfy { $0 < 3 || $0 > 252 }, "\(row)")
    }
}
