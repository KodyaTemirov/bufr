import Foundation
import Testing
@testable import Bufr

struct ExportCompatibilityTests {
    /// A pinboard item exported by Bufr 2.x: none of the 3.0 keys are present.
    private let legacyJSON = """
    {"clip_item":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","content_type":"text",
     "text_content":"hello","created_at":"2026-01-01T10:00:00Z","is_pinned":false,
     "is_favorite":false,"hash":"abc"},
     "sort_order":0,"added_at":"2026-01-01T10:00:00Z"}
    """

    @Test func legacyExportStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(ExportedClipItem.self, from: Data(legacyJSON.utf8))

        #expect(exported.clipItem.textContent == "hello")
        #expect(exported.clipItem.origin == nil)
        #expect(exported.clipItem.ocrText == nil)
    }

    @Test func withoutLocalPathsDropsMachineSpecificPaths() {
        let item = ClipItem(
            contentType: .image, imagePath: "c.png", hash: "h",
            origin: .screenshot, ocrText: "text", annotationPath: "c.annotations.json",
            savedFilePath: "/Users/me/Pictures/Bufr/c.png", pixelWidth: 10, pixelHeight: 20
        )
        let portable = item.withoutLocalPaths()

        #expect(portable.annotationPath == nil)
        #expect(portable.savedFilePath == nil)
        #expect(portable.origin == .screenshot)
        #expect(portable.ocrText == "text")
        #expect(portable.pixelWidth == 10)
    }

    /// Absolute paths contain the user name and mean nothing on another Mac.
    @Test func exportDropsLocalPaths() throws {
        let item = ClipItem(
            contentType: .image, imagePath: "c.png", hash: "h", origin: .screenshot,
            annotationPath: "c.annotations.json", savedFilePath: "/Users/someone/Pictures/Bufr/c.png"
        )

        let exported = ExportedClipItem(clipItem: item, sortOrder: 0, addedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(exported), as: UTF8.self)

        #expect(exported.clipItem.savedFilePath == nil)
        #expect(exported.clipItem.annotationPath == nil)
        #expect(!json.contains("/Users/"))
        #expect(exported.clipItem.origin == .screenshot)
    }
}
