import AppKit
import Carbon.HIToolbox
import QuartzCore

@MainActor
protocol CaptureOverlayViewDelegate: AnyObject {
    func overlayView(_ view: CaptureOverlayView, didSelect selection: CaptureSelection)
    func overlayViewDidCancel(_ view: CaptureOverlayView)
    func overlayView(_ view: CaptureOverlayView, didSwitchToWindowMode windowMode: Bool)
    func overlayViewDidRequestPreviousArea(_ view: CaptureOverlayView)
    func overlayViewMouseEntered(_ view: CaptureOverlayView)
    /// All-in-one mode: this view now holds the (only) editable selection
    func overlayViewDidAdjust(_ view: CaptureOverlayView)
}

extension CaptureOverlayViewDelegate {
    func overlayViewDidAdjust(_ view: CaptureOverlayView) {}
}

/// Frozen screen with selection UI for one display.
///
/// Layer-hosting and not flipped: views, events and layers all use Core Animation's
/// bottom-left origin. Rects are flipped to the display-local top-left convention only when
/// they leave this view (`ScreenGeometry.flipped`).
///
/// - Area mode: drag to select (⇧ square, ⌥ from centre, hold Space to move), release to capture.
/// - Window mode (Space before dragging): hover highlights a window, click captures it.
/// - Return captures the previous area, Esc cancels.
/// - Adjustable (all-in-one, ⌘⇧5): the selection stays after release — drag inside to move,
///   drag a handle to resize, arrows nudge (⇧ ×10), ⌥+arrows resize, Return captures.
final class CaptureOverlayView: NSView {
    struct Configuration {
        let image: CGImage
        let displayID: CGDirectDisplayID
        /// Cocoa global frame of the screen
        let screenFrame: CGRect
        let primaryHeight: CGFloat
        let backingScale: CGFloat
        /// CG global frames, front-to-back
        let windows: [CapturableWindow]
        let showMagnifier: Bool
        /// Adjustable mode only: selection to start with (view coordinates), e.g. the previous area
        var initialSelection: CGRect? = nil
    }

    weak var delegate: CaptureOverlayViewDelegate?

    var windowMode: Bool {
        didSet {
            guard windowMode != oldValue else { return }
            dragStart = nil
            selection = nil
            hoveredWindow = windowMode ? window(at: currentMousePoint()) : nil
            updateLayers(cursor: currentMousePoint())
        }
    }

    private let configuration: Configuration
    private let adjustable: Bool

    private enum DragKind {
        case create
        case move
        case resize(SelectionGeometry.Handle)
    }

    // Layers
    private let rootLayer = CALayer()
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let selectionBorder = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let loupeLayer = CALayer()
    private let loupeOverlay = CAShapeLayer()
    private let labelBackground = CALayer()
    private let labelText = CATextLayer()

    // Selection state (view coordinates, bottom-left origin)
    private var dragStart: CGPoint?
    private var dragKind: DragKind?
    private var lastDragPoint: CGPoint?
    private var selection: CGRect?
    private var spaceHeld = false
    private var hoveredWindow: CapturableWindow?

    private let minimumSelection: CGFloat = 4
    private let handleSize: CGFloat = 7
    private let loupeSize: CGFloat = 120
    private let loupePixels = 15 // odd, so there is a centre pixel

    init(configuration: Configuration, windowMode: Bool, adjustable: Bool = false) {
        self.configuration = configuration
        self.windowMode = windowMode
        self.adjustable = adjustable
        super.init(frame: CGRect(origin: .zero, size: configuration.screenFrame.size))
        if adjustable {
            selection = configuration.initialSelection
        }

        // Layer-hosting: assign the layer before enabling wantsLayer
        layer = rootLayer
        wantsLayer = true
        setUpLayers()
        updateLayers(cursor: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setUpLayers() {
        let scale = configuration.backingScale
        rootLayer.contentsScale = scale

        imageLayer.contents = configuration.image
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = CGFloat(configuration.image.width) / max(bounds.width, 1)
        imageLayer.frame = bounds

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.frame = bounds

        highlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        highlightLayer.strokeColor = NSColor.controlAccentColor.cgColor
        highlightLayer.lineWidth = 2
        highlightLayer.frame = bounds

        selectionBorder.fillColor = nil
        selectionBorder.strokeColor = NSColor.white.cgColor
        selectionBorder.lineWidth = 1
        selectionBorder.frame = bounds

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
        handlesLayer.lineWidth = 0.5
        handlesLayer.frame = bounds

        loupeLayer.magnificationFilter = .nearest
        loupeLayer.contentsGravity = .resize
        loupeLayer.cornerRadius = 8
        loupeLayer.masksToBounds = true
        loupeLayer.borderColor = NSColor.white.cgColor
        loupeLayer.borderWidth = 2
        loupeLayer.backgroundColor = NSColor.black.cgColor

        loupeOverlay.fillColor = nil
        loupeOverlay.strokeColor = NSColor.white.cgColor
        loupeOverlay.lineWidth = 1.5

        labelBackground.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        labelBackground.cornerRadius = 5
        labelText.alignmentMode = .center
        labelText.contentsScale = scale
        labelBackground.addSublayer(labelText)

        for sublayer in [imageLayer, dimLayer, highlightLayer, selectionBorder, handlesLayer, loupeLayer, loupeOverlay, labelBackground] {
            sublayer.contentsScale = sublayer === imageLayer ? sublayer.contentsScale : scale
            rootLayer.addSublayer(sublayer)
        }
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if windowMode {
            hoveredWindow = window(at: currentMousePoint())
            updateLayers(cursor: currentMousePoint())
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.overlayViewMouseEntered(self)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        // The loupe and hover highlight belong to the screen under the mouse only
        hoveredWindow = nil
        updateLayers(cursor: nil)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        if windowMode {
            hoveredWindow = window(at: point)
        }
        updateLayers(cursor: point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if windowMode {
            if let hovered = window(at: point) {
                delegate?.overlayView(self, didSelect: .window(hovered))
            }
            return
        }
        lastDragPoint = point
        if adjustable, let current = selection, !current.isEmpty {
            // Small selections shrink the handle hit area so their middle still moves them
            let tolerance = min(handleSize, min(current.width, current.height) / 4)
            if let handle = SelectionGeometry.handle(at: point, in: current, tolerance: tolerance) {
                dragKind = .resize(handle)
                return
            }
            if current.contains(point) {
                dragKind = .move
                return
            }
        }
        dragKind = .create
        dragStart = point
        selection = CGRect(origin: point, size: .zero)
        updateLayers(cursor: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch dragKind {
        case .move:
            if let current = selection, let last = lastDragPoint {
                selection = SelectionGeometry.moved(current, by: CGSize(width: point.x - last.x, height: point.y - last.y), within: bounds)
            }
            lastDragPoint = point
            updateLayers(cursor: point)
            return
        case .resize(let handle):
            if let current = selection {
                selection = SelectionGeometry.resized(current, handle: handle, to: point, bounds: bounds, minimumSize: minimumSelection)
            }
            lastDragPoint = point
            updateLayers(cursor: point)
            return
        case .create, nil:
            break
        }

        guard let start = dragStart else { return }

        if spaceHeld, let current = selection, let last = lastDragPoint {
            let moved = SelectionGeometry.moved(
                current,
                by: CGSize(width: point.x - last.x, height: point.y - last.y),
                within: bounds
            )
            // Move the anchor with the rect so resizing continues smoothly after Space is released
            dragStart = CGPoint(x: start.x + moved.minX - current.minX, y: start.y + moved.minY - current.minY)
            selection = moved
        } else {
            selection = SelectionGeometry.rect(
                from: start, to: point,
                square: event.modifierFlags.contains(.shift),
                fromCenter: event.modifierFlags.contains(.option),
                bounds: bounds
            )
        }
        lastDragPoint = point
        updateLayers(cursor: point)
    }

    override func mouseUp(with event: NSEvent) {
        let kind = dragKind
        dragKind = nil

        if adjustable {
            dragStart = nil
            lastDragPoint = nil
            spaceHeld = false
            if let rect = selection, rect.width >= minimumSelection, rect.height >= minimumSelection {
                delegate?.overlayViewDidAdjust(self)
            } else if case .create = kind {
                selection = nil
            }
            updateLayers(cursor: convert(event.locationInWindow, from: nil))
            return
        }

        guard dragStart != nil else { return }
        dragStart = nil
        lastDragPoint = nil
        spaceHeld = false

        guard let rect = selection, rect.width >= minimumSelection, rect.height >= minimumSelection else {
            selection = nil
            updateLayers(cursor: convert(event.locationInWindow, from: nil))
            return
        }
        let localRect = ScreenGeometry.flipped(rect, height: bounds.height)
        delegate?.overlayView(self, didSelect: .area(displayID: configuration.displayID, localRect: localRect))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            delegate?.overlayViewDidCancel(self)
        case kVK_Space:
            if dragStart != nil {
                spaceHeld = true
            } else if !event.isARepeat {
                delegate?.overlayView(self, didSwitchToWindowMode: !windowMode)
            }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if adjustable {
                if let localRect = adjustedLocalSelection {
                    delegate?.overlayView(self, didSelect: .area(displayID: configuration.displayID, localRect: localRect))
                }
            } else if dragStart == nil {
                delegate?.overlayViewDidRequestPreviousArea(self)
            }
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            adjustWithArrow(Int(event.keyCode), modifiers: event.modifierFlags)
        default:
            break // swallow: no beeps while capturing
        }
    }

    /// The editable selection as a display-local rect (top-left origin), if it is usable.
    var adjustedLocalSelection: CGRect? {
        guard adjustable, !windowMode, let rect = selection,
              rect.width >= minimumSelection, rect.height >= minimumSelection
        else { return nil }
        return ScreenGeometry.flipped(rect, height: bounds.height)
    }

    /// Another display took over the editable selection.
    func clearSelection() {
        selection = nil
        dragKind = nil
        dragStart = nil
        updateLayers(cursor: nil)
    }

    private func adjustWithArrow(_ keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        guard adjustable, !windowMode, let current = selection else { return }
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
        let (dx, dy): (CGFloat, CGFloat) = switch keyCode {
        case kVK_LeftArrow: (-step, 0)
        case kVK_RightArrow: (step, 0)
        case kVK_UpArrow: (0, step)   // the view's y grows upward
        default: (0, -step)
        }
        if modifiers.contains(.option) {
            // ⌥→ wider, ⌥↓ taller: the top-left corner stays put
            selection = SelectionGeometry.grown(current, dWidth: dx, dHeight: -dy, bounds: bounds, minimumSize: minimumSelection)
        } else {
            selection = SelectionGeometry.nudged(current, dx: dx, dy: dy, bounds: bounds)
        }
        updateLayers(cursor: nil)
    }

    override func keyUp(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space {
            spaceHeld = false
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // ⇧ / ⌥ pressed mid-drag reshape the selection immediately
        guard let start = dragStart, let last = lastDragPoint, !spaceHeld else { return }
        selection = SelectionGeometry.rect(
            from: start, to: last,
            square: event.modifierFlags.contains(.shift),
            fromCenter: event.modifierFlags.contains(.option),
            bounds: bounds
        )
        updateLayers(cursor: last)
    }

    // MARK: - Windows

    private func window(at viewPoint: CGPoint?) -> CapturableWindow? {
        guard let viewPoint, bounds.contains(viewPoint) else { return nil }
        let cocoaGlobal = CGPoint(
            x: configuration.screenFrame.minX + viewPoint.x,
            y: configuration.screenFrame.minY + viewPoint.y
        )
        let cgGlobal = ScreenGeometry.cgPoint(fromCocoa: cocoaGlobal, primaryHeight: configuration.primaryHeight)
        return WindowPicker.window(at: cgGlobal, in: configuration.windows)
    }

    private func viewRect(forCGGlobal rect: CGRect) -> CGRect {
        ScreenGeometry.cocoaRect(fromCG: rect, primaryHeight: configuration.primaryHeight)
            .offsetBy(dx: -configuration.screenFrame.minX, dy: -configuration.screenFrame.minY)
    }

    private func currentMousePoint() -> CGPoint? {
        guard let window else { return nil }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return bounds.contains(point) ? point : nil
    }

    // MARK: - Drawing

    private func updateLayers(cursor: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let hole: CGRect?
        if windowMode {
            hole = hoveredWindow.map { viewRect(forCGGlobal: $0.frame).intersection(bounds) }
        } else {
            hole = selection
        }

        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let hole, !hole.isEmpty {
            dimPath.addRect(hole)
        }
        dimLayer.path = dimPath

        if windowMode, let hole, !hole.isEmpty {
            highlightLayer.path = CGPath(rect: hole.insetBy(dx: 1, dy: 1), transform: nil)
        } else {
            highlightLayer.path = nil
        }

        if !windowMode, let rect = selection, !rect.isEmpty {
            selectionBorder.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
        } else {
            selectionBorder.path = nil
        }

        if adjustable, !windowMode, dragKind == nil || isResizingOrMoving, let rect = selection, !rect.isEmpty {
            let handles = CGMutablePath()
            for handle in SelectionGeometry.Handle.allCases {
                let center = handle.point(in: rect)
                handles.addRect(CGRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize))
            }
            handlesLayer.path = handles
        } else {
            handlesLayer.path = nil
        }

        if let hole, !hole.isEmpty {
            showSizeLabel(for: hole)
        } else {
            labelBackground.isHidden = true
        }

        if configuration.showMagnifier, !windowMode, let cursor {
            showLoupe(at: cursor)
        } else {
            loupeLayer.isHidden = true
            loupeOverlay.isHidden = true
        }
    }

    private var isResizingOrMoving: Bool {
        switch dragKind {
        case .move, .resize: true
        case .create, nil: false
        }
    }

    private func showSizeLabel(for rect: CGRect) {
        let pixels = ScreenGeometry.pixelRect(
            forLocal: ScreenGeometry.flipped(rect, height: bounds.height),
            displayPointSize: bounds.size,
            imagePixelSize: CGSize(width: configuration.image.width, height: configuration.image.height)
        )
        guard !pixels.isNull else {
            labelBackground.isHidden = true
            return
        }

        let text = NSAttributedString(string: "\(Int(pixels.width)) × \(Int(pixels.height))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        let size = CGSize(width: ceil(textSize.width) + 12, height: ceil(textSize.height) + 6)

        // Below the selection; inside it when there is no room (bottom edge of the screen)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 6)
        if origin.y < bounds.minY + 4 {
            origin.y = rect.minY + 6
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)

        labelText.string = text
        labelBackground.frame = CGRect(origin: origin, size: size)
        labelText.frame = CGRect(x: 0, y: 3, width: size.width, height: ceil(textSize.height))
        labelBackground.isHidden = false
    }

    private func showLoupe(at cursor: CGPoint) {
        let image = configuration.image
        let scale = CGFloat(image.width) / bounds.width
        let topLeft = ScreenGeometry.flipped(cursor, height: bounds.height)
        let centerX = Int(topLeft.x * scale)
        let centerY = Int(topLeft.y * scale)
        let half = loupePixels / 2
        let source = CGRect(x: centerX - half, y: centerY - half, width: loupePixels, height: loupePixels)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !source.isNull, let pixels = image.cropping(to: source) else {
            loupeLayer.isHidden = true
            loupeOverlay.isHidden = true
            return
        }

        // Bottom-right of the cursor, flipped to the other side near screen edges
        var origin = CGPoint(x: cursor.x + 24, y: cursor.y - 24 - loupeSize)
        if origin.x + loupeSize > bounds.maxX { origin.x = cursor.x - 24 - loupeSize }
        if origin.y < bounds.minY { origin.y = cursor.y + 24 }
        let frame = CGRect(origin: origin, size: CGSize(width: loupeSize, height: loupeSize))

        loupeLayer.contents = pixels
        loupeLayer.frame = frame
        loupeLayer.isHidden = false

        // Outline of the pixel under the cursor
        let cell = loupeSize / CGFloat(loupePixels)
        let center = CGRect(x: frame.minX + cell * CGFloat(half), y: frame.minY + cell * CGFloat(half), width: cell, height: cell)
        loupeOverlay.frame = bounds
        loupeOverlay.path = CGPath(rect: center, transform: nil)
        loupeOverlay.isHidden = false
    }
}
