import Foundation
import GRDB

/// Where a history item came from. `nil` in the database means a row created before Bufr 3.0
/// (always clipboard).
enum ClipOrigin: String, Codable, Sendable, DatabaseValueConvertible {
    case clipboard
    case screenshot
    case textCapture = "text_capture"
}
