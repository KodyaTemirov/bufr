import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Bufr

/// The menu bar logo is a template: a rounded square with the letter cut out.
struct MenuBarIconTests {
    private func image(_ name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/\(name)")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func bothScalesExist() throws {
        #expect(try image("MenuBarIcon.png").width == 16)
        #expect(try image("MenuBarIcon@2x.png").width == 32)
    }

    @Test func squareIsSolidWithTheLetterCutOut() throws {
        let icon = try image("MenuBarIcon@2x.png")
        let alphas = (0..<32).flatMap { y in (0..<32).map { x in TestImages.pixel(icon, x, y)[3] } }
        let alpha = { (x: Int, y: Int) in alphas[y * 32 + x] }

        #expect(alpha(0, 0) < 40) // rounded corner
        #expect(alpha(3, 16) > 220) // the square's body, left of the letter
        let middle = (8..<24).flatMap { y in (8..<24).map { x in alpha(x, y) } }
        #expect(middle.filter { $0 < 40 }.count > 40) // the cut-out letter
    }

    @MainActor
    @Test func loadedIconIsATemplate() {
        #expect(MenuBarIcon.image.isTemplate)
    }
}
