import Foundation
import Testing

struct LocalizationTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func keys(_ language: String) -> Set<String> {
        let url = root.appendingPathComponent("Sources/Resources/\(language).lproj/Localizable.strings")
        let table = NSDictionary(contentsOf: url) as? [String: String] ?? [:]
        return Set(table.keys)
    }

    @Test func allLanguagesHaveTheSameKeys() {
        let english = Self.keys("en")

        #expect(!english.isEmpty)
        #expect(Self.keys("ru").symmetricDifference(english).sorted() == [])
        #expect(Self.keys("uz").symmetricDifference(english).sorted() == [])
    }

    /// Every literal passed to L10n(...) in the app must exist, or the raw key shows up in the UI.
    @Test func everyUsedKeyExists() throws {
        let english = Self.keys("en")
        let sources = Self.root.appendingPathComponent("Sources")
        let regex = try NSRegularExpression(pattern: #"L10n\("([A-Za-z0-9_.]+)""#)
        var missing: Set<String> = []

        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let keyRange = Range(match.range(at: 1), in: text) {
                    let key = String(text[keyRange])
                    if !english.contains(key) { missing.insert(key) }
                }
            }
        }

        #expect(missing.sorted() == [])
    }
}
