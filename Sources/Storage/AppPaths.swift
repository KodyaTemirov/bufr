import Foundation

enum AppPaths {
    /// ~/Library/Application Support/Bufr
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bufr", isDirectory: true)
}
