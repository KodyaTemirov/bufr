import AppKit
import Carbon.HIToolbox
import Testing
@testable import Bufr

@MainActor
final class OverlayDelegateSpy: CaptureOverlayViewDelegate {
    var selections: [CaptureSelection] = []
    var cancelled = false
    var windowModeRequests: [Bool] = []
    var captureRequests = 0

    func overlayView(_ view: CaptureOverlayView, didSelect selection: CaptureSelection) { selections.append(selection) }
    func overlayViewDidCancel(_ view: CaptureOverlayView) { cancelled = true }
    func overlayView(_ view: CaptureOverlayView, didSwitchToWindowMode windowMode: Bool) { windowModeRequests.append(windowMode) }
    func overlayViewDidRequestPreviousArea(_ view: CaptureOverlayView) {}
    func overlayViewMouseEntered(_ view: CaptureOverlayView) {}
    func overlayViewDidRequestCapture(_ view: CaptureOverlayView) { captureRequests += 1 }
}

/// A 100×50 pt screen at the Cocoa origin (so view points equal Cocoa global points).
@MainActor
struct CaptureOverlayViewTests {
    let spy = OverlayDelegateSpy()

    private func makeView(windows: [CapturableWindow] = [], windowMode: Bool = false) -> CaptureOverlayView {
        let view = CaptureOverlayView(
            configuration: .init(
                image: TestImages.cgImage(width: 200, height: 100),
                displayID: 7,
                screenFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
                primaryHeight: 50,
                backingScale: 2,
                windows: windows,
                showMagnifier: true
            ),
            windowMode: windowMode
        )
        view.delegate = spy
        return view
    }

    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    @Test func dragReportsTopLeftDisplayRect() {
        let view = makeView()

        view.mouseDown(with: mouse(.leftMouseDown, 10, 40))
        view.mouseDragged(with: mouse(.leftMouseDragged, 30, 30))
        view.mouseUp(with: mouse(.leftMouseUp, 30, 30))

        // View rect (10, 30, 20, 10) with a bottom-left origin is (10, 10, 20, 10) from the top
        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 10, y: 10, width: 20, height: 10))])
    }

    @Test func tinyDragIsIgnored() {
        let view = makeView()

        view.mouseDown(with: mouse(.leftMouseDown, 10, 10))
        view.mouseUp(with: mouse(.leftMouseUp, 12, 12))

        #expect(spy.selections.isEmpty)
    }

    /// The window occupies the top-left quarter in CG coordinates (y down).
    @Test func windowModeClickPicksWindowUnderCursor() {
        let window = CapturableWindow(windowID: 42, frame: CGRect(x: 0, y: 0, width: 50, height: 25),
                                      ownerPID: 1, ownerName: "App", title: nil)
        let view = makeView(windows: [window], windowMode: true)

        view.mouseDown(with: mouse(.leftMouseDown, 10, 45)) // near the top of the screen
        view.mouseDown(with: mouse(.leftMouseDown, 10, 5))  // bottom: no window there

        #expect(spy.selections == [.window(window)])
    }

    @Test func spaceBeforeDragAsksForWindowMode() {
        let view = makeView()
        let space = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: UInt16(kVK_Space)
        )!

        view.keyDown(with: space)

        #expect(spy.windowModeRequests == [true])
    }

    /// A 1920×1080 display above and to the left of a 900 pt tall primary display.
    private func makeSecondaryView(windows: [CapturableWindow], windowMode: Bool) -> CaptureOverlayView {
        let view = CaptureOverlayView(
            configuration: .init(
                image: TestImages.cgImage(width: 3840, height: 2160),
                displayID: 9,
                screenFrame: CGRect(x: -1920, y: 900, width: 1920, height: 1080),
                primaryHeight: 900,
                backingScale: 2,
                windows: windows,
                showMagnifier: false
            ),
            windowMode: windowMode
        )
        view.delegate = spy
        return view
    }

    @Test func secondaryDisplayWindowPick() {
        let window = CapturableWindow(windowID: 5, frame: CGRect(x: -1900, y: -1060, width: 400, height: 300),
                                      ownerPID: 1, ownerName: nil, title: nil)
        let view = makeSecondaryView(windows: [window], windowMode: true)

        view.mouseDown(with: mouse(.leftMouseDown, 100, 1000)) // Cocoa (-1820, 1900) = CG (-1820, -1000)

        #expect(spy.selections == [.window(window)])
    }

    @Test func secondaryDisplayAreaIsDisplayLocal() {
        let view = makeSecondaryView(windows: [], windowMode: false)

        view.mouseDown(with: mouse(.leftMouseDown, 100, 1000))
        view.mouseDragged(with: mouse(.leftMouseDragged, 300, 900))
        view.mouseUp(with: mouse(.leftMouseUp, 300, 900))

        #expect(spy.selections == [.area(displayID: 9, localRect: CGRect(x: 100, y: 80, width: 200, height: 100))])
    }

    // MARK: - All-in-one (adjustable selection)

    private func makeAdjustableView(initialSelection: CGRect? = nil) -> CaptureOverlayView {
        let view = CaptureOverlayView(
            configuration: .init(
                image: TestImages.cgImage(width: 200, height: 100),
                displayID: 7,
                screenFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
                primaryHeight: 50,
                backingScale: 2,
                windows: [],
                showMagnifier: false,
                initialSelection: initialSelection
            ),
            windowMode: false,
            adjustable: true
        )
        view.delegate = spy
        return view
    }

    private func key(_ code: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)
        )!
    }

    @Test func adjustableSelectionWaitsForReturn() {
        let view = makeAdjustableView()

        view.mouseDown(with: mouse(.leftMouseDown, 10, 40))
        view.mouseDragged(with: mouse(.leftMouseDragged, 30, 30))
        view.mouseUp(with: mouse(.leftMouseUp, 30, 30))
        #expect(spy.selections.isEmpty)

        view.keyDown(with: key(kVK_Return))
        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 10, y: 10, width: 20, height: 10))])
    }

    @Test func draggingInsideMovesTheSelection() {
        let view = makeAdjustableView()
        view.mouseDown(with: mouse(.leftMouseDown, 10, 40))
        view.mouseDragged(with: mouse(.leftMouseDragged, 30, 30))
        view.mouseUp(with: mouse(.leftMouseUp, 30, 30))

        view.mouseDown(with: mouse(.leftMouseDown, 20, 35))
        view.mouseDragged(with: mouse(.leftMouseDragged, 25, 35))
        view.mouseUp(with: mouse(.leftMouseUp, 25, 35))
        view.keyDown(with: key(kVK_Return))

        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 15, y: 10, width: 20, height: 10))])
    }

    @Test func arrowsNudgeAndOptionArrowsResize() {
        let view = makeAdjustableView(initialSelection: CGRect(x: 10, y: 20, width: 20, height: 10))

        view.keyDown(with: key(kVK_RightArrow))
        view.keyDown(with: key(kVK_DownArrow, .shift))  // 10 pt down (the view's y grows upward)
        view.keyDown(with: key(kVK_RightArrow, .option)) // 1 pt wider
        view.keyDown(with: key(kVK_Return))

        // View rect (11, 10, 21, 10) → top-left display rect
        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 11, y: 30, width: 21, height: 10))])
    }

    @Test func previousAreaIsPreselected() {
        let view = makeAdjustableView(initialSelection: CGRect(x: 5, y: 5, width: 40, height: 20))

        view.keyDown(with: key(kVK_Return))

        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 5, y: 25, width: 40, height: 20))])
    }

    /// The selection may live on another display; the session decides what Return captures.
    @Test func returnWithoutOwnSelectionAsksTheSession() {
        let view = makeAdjustableView()

        view.keyDown(with: key(kVK_Return))

        #expect(spy.selections.isEmpty)
        #expect(spy.captureRequests == 1)
    }

    /// After "Screen" the whole display may be preselected; dragging must still draw a new area.
    @Test func dragInsideFullScreenSelectionDrawsNewArea() {
        let view = makeAdjustableView(initialSelection: CGRect(x: 0, y: 0, width: 100, height: 50))

        view.mouseDown(with: mouse(.leftMouseDown, 20, 40))
        view.mouseDragged(with: mouse(.leftMouseDragged, 40, 30))
        view.mouseUp(with: mouse(.leftMouseUp, 40, 30))
        view.keyDown(with: key(kVK_Return))

        #expect(spy.selections == [.area(displayID: 7, localRect: CGRect(x: 20, y: 10, width: 20, height: 10))])
    }
}
