import AppKit
import Testing
@testable import Bufr

@MainActor
struct PasteboardWriterTests {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bufr.tests.\(UUID().uuidString)"))

    @Test func writeTextMarksSelfWrite() {
        PasteboardWriter.writeText("hello", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
    }

    @Test func writeImageOffersPNGAndLazyTIFF() throws {
        PasteboardWriter.writeImage(png: TestImages.png(width: 3, height: 2), to: pasteboard)

        #expect(pasteboard.types?.contains(.png) == true)
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
        let tiff = try #require(pasteboard.data(forType: .tiff))
        #expect(NSBitmapImageRep(data: tiff)?.pixelsWide == 3)
    }

    /// History files written before 3.0 may contain TIFF bytes under a .png name.
    @Test func writeImageNormalizesLegacyTIFFBytes() throws {
        let written = PasteboardWriter.writeImage(anyImageData: TestImages.tiff(), to: pasteboard)

        #expect(written)
        let png = try #require(pasteboard.data(forType: .png))
        #expect(Array(png.prefix(4)) == TestImages.pngSignature)
    }

    @Test func writeImageRejectsGarbage() {
        #expect(PasteboardWriter.writeImage(anyImageData: Data([1, 2, 3]), to: pasteboard) == false)
    }

    @Test func writeFileItemKeepsURLsAndMarker() {
        let item = ClipItem(
            contentType: .file,
            filePaths: ClipItem.encodeFilePaths(["/tmp/bufr-test.txt"]),
            hash: "f"
        )

        PasteboardWriter.write(item, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls == [URL(fileURLWithPath: "/tmp/bufr-test.txt")])
        #expect(pasteboard.types?.contains(.bufrSelfWrite) == true)
    }

    @Test func writeRichTextKeepsPlainFallback() {
        let rtf = Data("{\\rtf1 hi}".utf8)
        let item = ClipItem(contentType: .richText, textContent: "hi", richContent: rtf, hash: "r")

        PasteboardWriter.write(item, to: pasteboard)

        #expect(pasteboard.data(forType: .rtf) == rtf)
        #expect(pasteboard.string(forType: .string) == "hi")
    }
}
