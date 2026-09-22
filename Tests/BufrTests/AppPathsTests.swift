import Foundation
import Testing
@testable import Bufr

struct AppPathsTests {
    /// Debug builds erase the database on schema changes; they must never open the installed
    /// app's history in ~/Library/Application Support/Bufr.
    @Test func debugBuildsUseSeparateDataFolder() {
        #if DEBUG
        #expect(AppPaths.support.lastPathComponent == "Bufr-Debug")
        #else
        #expect(AppPaths.support.lastPathComponent == "Bufr")
        #endif
    }
}
