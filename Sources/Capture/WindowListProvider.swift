import CoreGraphics
import Foundation

enum WindowListProvider {
    /// Smaller windows are usually invisible helpers (tooltips, status items)
    static let minimumSize: CGFloat = 40

    /// Front-to-back list of normal on-screen windows, excluding Bufr's own.
    static func snapshot() -> [CapturableWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return parse(info, excludingPID: getpid())
    }

    /// Keeps layer-0 (normal) windows that are visible and large enough; order is preserved.
    static func parse(_ info: [[String: Any]], excludingPID: pid_t) -> [CapturableWindow] {
        info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  pid_t(pid) != excludingPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= minimumSize, frame.height >= minimumSize
            else { return nil }

            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                return nil
            }

            return CapturableWindow(
                windowID: CGWindowID(number),
                frame: frame,
                ownerPID: pid_t(pid),
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                title: entry[kCGWindowName as String] as? String
            )
        }
    }
}
