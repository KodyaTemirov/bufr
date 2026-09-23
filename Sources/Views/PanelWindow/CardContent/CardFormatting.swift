import AppKit

/// How a clipboard text looks on its card.
enum CardText {
    /// Code gets a monospaced font, everything else the system font. At least two independent
    /// signs are needed, so a sentence with one semicolon stays prose.
    static func isCode(_ text: String) -> Bool {
        let sample = String(text.prefix(2000))
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: false)
        var signs = 0
        if sample.contains("{"), sample.contains("}") { signs += 1 }
        if ["=>", "->", "==", "!=", "::"].contains(where: sample.contains) { signs += 1 }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }) { signs += 1 }
        if lines.count >= 2, lines.contains(where: { $0.hasPrefix("  ") || $0.hasPrefix("\t") }) { signs += 1 }
        let keywords = ["func ", "let ", "var ", "const ", "def ", "class ", "import ", "return ", "#include",
                        "public ", "private ", "function ", "SELECT ", "UPDATE ", "</", "<div", "if (", "for ("]
        if keywords.contains(where: sample.contains) { signs += 1 }
        if sample.contains("("), sample.contains(")"), sample.contains("=") { signs += 1 }
        return signs >= 2
    }
}

/// A link shown as its site, big, and the rest, small.
struct URLParts: Equatable {
    let host: String
    /// Path and query; empty for the site's front page
    let path: String

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        var rest = url.path(percentEncoded: false)
        if rest == "/" {
            rest = ""
        }
        if let query = url.query(percentEncoded: false), !query.isEmpty {
            rest += "?" + query
        }
        self.host = host
        self.path = rest
    }
}

extension ColorExtractor {
    /// "RGB 255 128 0" for a hex colour; nil when it isn't one.
    static func rgbDescription(_ hex: String) -> String? {
        guard let color = parseHexColor(hex)?.usingColorSpace(.sRGB) else { return nil }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        return "RGB " + channels.map(String.init).joined(separator: " ")
    }
}
