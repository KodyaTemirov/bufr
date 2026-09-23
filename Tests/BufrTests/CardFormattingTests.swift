import Testing
@testable import Bufr

struct CardFormattingTests {
    @Test func codeIsRecognized() {
        #expect(CardText.isCode("func main() {\n    print(1)\n}"))
        #expect(CardText.isCode("const total = items.reduce((a, b) => a + b, 0);"))
        #expect(CardText.isCode("<div class=\"card\">\n  <span>Hi</span>\n</div>"))
        #expect(CardText.isCode("SELECT id, name FROM users WHERE id = 1;\nORDER BY name;"))
    }

    @Test func proseIsNotCode() {
        #expect(!CardText.isCode("Привет! Завтра встреча в 10:00, не забудь документы."))
        #expect(!CardText.isCode("One sentence; then another, with a comma."))
        #expect(!CardText.isCode("Список покупок:\n- молоко\n- хлеб"))
    }

    @Test func linkIsSplitIntoSiteAndPath() {
        let parts = URLParts(string: "https://www.github.com/KodyaTemirov/bufr?tab=readme")

        #expect(parts?.host == "github.com")
        #expect(parts?.path == "/KodyaTemirov/bufr?tab=readme")
        #expect(URLParts(string: "https://example.com")?.path == "")
        #expect(URLParts(string: "не ссылка") == nil)
    }

    @Test func colorGetsItsRGBValues() {
        #expect(ColorExtractor.rgbDescription("#FF8000") == "RGB 255 128 0")
        #expect(ColorExtractor.rgbDescription("#fff") == "RGB 255 255 255")
        #expect(ColorExtractor.rgbDescription("purple") == nil)
    }
}
