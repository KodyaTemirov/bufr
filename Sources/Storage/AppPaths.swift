import Foundation

enum AppPaths {
    /// ~/Library/Application Support/Bufr. Debug builds use "Bufr-Debug": they erase the
    /// database on schema changes and must never open the installed app's history.
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(folderName, isDirectory: true)

    #if DEBUG
    private static let folderName = "Bufr-Debug"
    #else
    private static let folderName = "Bufr"
    #endif
}
