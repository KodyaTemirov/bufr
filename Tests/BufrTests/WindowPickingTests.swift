import CoreGraphics
import Foundation
import Testing
@testable import Bufr

struct WindowPickingTests {
    private func info(
        number: Int, pid: Int, layer: Int = 0, alpha: Double = 1,
        frame: CGRect, owner: String = "App", title: String? = nil
    ) -> [String: Any] {
        var entry: [String: Any] = [
            kCGWindowNumber as String: number,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary,
            kCGWindowOwnerName as String: owner,
        ]
        if let title { entry[kCGWindowName as String] = title }
        return entry
    }

    @Test func parseKeepsOnlyCapturableWindows() {
        let windows = WindowListProvider.parse([
            info(number: 1, pid: 10, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "Doc"),
            info(number: 2, pid: 10, layer: 25, frame: CGRect(x: 0, y: 0, width: 800, height: 25)),   // menu bar
            info(number: 3, pid: 10, alpha: 0, frame: CGRect(x: 0, y: 0, width: 300, height: 300)),   // invisible
            info(number: 4, pid: 10, frame: CGRect(x: 0, y: 0, width: 20, height: 300)),              // too thin
            info(number: 5, pid: 99, frame: CGRect(x: 0, y: 0, width: 500, height: 500)),             // Bufr itself
        ], excludingPID: 99)

        #expect(windows == [CapturableWindow(
            windowID: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            ownerPID: 10, ownerName: "App", title: "Doc"
        )])
    }

    @Test func pickerReturnsFrontmostWindowUnderPoint() {
        let front = CapturableWindow(windowID: 1, frame: CGRect(x: 100, y: 100, width: 200, height: 200),
                                     ownerPID: 1, ownerName: nil, title: nil)
        let back = CapturableWindow(windowID: 2, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                    ownerPID: 2, ownerName: nil, title: nil)

        #expect(WindowPicker.window(at: CGPoint(x: 150, y: 150), in: [front, back]) == front)
        #expect(WindowPicker.window(at: CGPoint(x: 50, y: 50), in: [front, back]) == back)
        #expect(WindowPicker.window(at: CGPoint(x: 5000, y: 5000), in: [front, back]) == nil)
    }
}
