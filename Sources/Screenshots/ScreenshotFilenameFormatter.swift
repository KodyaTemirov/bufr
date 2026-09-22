import Foundation

/// "Screenshot 2026-09-23 at 14.05.12.png" — the same shape macOS uses.
enum ScreenshotFilenameFormatter {
    static let maxLength = 200

    static func baseName(prefix: String, connector: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // Latin digits in every UI language
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: date)

        let parts = [sanitize(prefix), day, connector, time].filter { !$0.isEmpty }
        return String(parts.joined(separator: " ").prefix(maxLength))
    }

    /// "/" and ":" are path separators for the file system and Finder; control characters are dropped.
    static func sanitize(_ text: String) -> String {
        let replaced = text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let scalars = replaced.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "name.png", then "name (2).png", "name (3).png", … — the first one `exists` rejects.
    static func availableFilename(baseName: String, pathExtension: String = "png", exists: (String) -> Bool) -> String {
        var candidate = "\(baseName).\(pathExtension)"
        var number = 2
        while exists(candidate) {
            candidate = "\(baseName) (\(number)).\(pathExtension)"
            number += 1
        }
        return candidate
    }
}
