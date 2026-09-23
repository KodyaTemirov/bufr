import CoreGraphics
import Foundation
import Testing
@testable import Bufr

/// "Share" sends what the editor shows now, as a PNG named like the screenshot.
struct EditorShareFileTests {
    @Test func writesTheCurrentResultUnderTheScreenshotsName() throws {
        let directory = try TestSupport.makeTempDirectory()
        var document = AnnotationDocument(baseImageFilename: "b", pixelWidth: 100, pixelHeight: 60, pointScale: 2)
        document.add(Annotation(shape: .filledRectangle(CGRect(x: 0, y: 0, width: 20, height: 20)), style: AnnotationStyle(color: .red, lineWidth: 4, fontSize: 20)))

        let url = try EditorShareFile.write(document, base: TestImages.blank(width: 100, height: 60), filename: "Shot 1.png", in: directory)

        #expect(url.lastPathComponent == "Shot 1.png")
        let image = try #require(TestImages.decode(try Data(contentsOf: url)))
        let corner = TestImages.pixel(image, 5, 5)
        #expect(image.width == 100 && image.height == 60)
        #expect(corner[0] > 200 && corner[1] < 90)
    }

    /// Two shares of the same screenshot must not overwrite a file another app is still reading.
    @Test func eachShareGetsItsOwnFile() throws {
        let directory = try TestSupport.makeTempDirectory()
        let document = AnnotationDocument(baseImageFilename: "b", pixelWidth: 10, pixelHeight: 10, pointScale: 1)
        let base = TestImages.blank(width: 10, height: 10)

        let first = try EditorShareFile.write(document, base: base, filename: "Shot.png", in: directory)
        let second = try EditorShareFile.write(document, base: base, filename: "Shot.png", in: directory)

        #expect(first != second)
    }
}
