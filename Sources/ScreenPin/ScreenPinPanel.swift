import AppKit

/// A screenshot floating above all windows. Drag to move, scroll to change opacity,
/// pinch to zoom, arrows to nudge, L to lock (clicks pass through), Esc to close.
final class ScreenPinPanel: NSPanel {
    let pinID = UUID()
    private(set) var item: ClipItem
    weak var manager: ScreenPinManager?

    var isLocked = false {
        didSet {
            ignoresMouseEvents = isLocked
            pinView.setLocked(isLocked)
        }
    }

    private let pinView: ScreenPinView
    /// Point size of the image; "Reset Size" returns to it
    private var naturalSize: CGSize

    init(item: ClipItem, image: NSImage, frame: CGRect) {
        self.item = item
        self.naturalSize = image.size
        self.pinView = ScreenPinView(image: image)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentAspectRatio = image.size
        minSize = CGSize(width: 40, height: 40)
        contentView = pinView
        pinView.panel = self
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func nudge(dx: CGFloat, dy: CGFloat) {
        setFrameOrigin(CGPoint(x: frame.minX + dx, y: frame.minY + dy))
    }

    /// Scales around the centre, keeping the aspect ratio.
    func zoom(by factor: CGFloat) {
        let width = max(minSize.width, frame.width * factor)
        let height = width * frame.height / frame.width
        setFrame(CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true)
    }

    func resetSize() {
        let visible = screen?.visibleFrame ?? frame
        let size = ScreenPinGeometry.fitted(naturalSize, within: visible.size)
        let target = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        setFrame(ScreenPinGeometry.clamped(target, to: visible), display: true, animate: true)
    }

    /// Shows a newer version of the same item (e.g. after editing), keeping position and height.
    func update(item: ClipItem, image: NSImage) {
        self.item = item
        naturalSize = image.size
        contentAspectRatio = image.size
        pinView.setImage(image)
        let height = frame.height
        let width = height * image.size.width / max(image.size.height, 1)
        setFrame(CGRect(x: frame.minX, y: frame.minY, width: width, height: height), display: true)
    }
}
