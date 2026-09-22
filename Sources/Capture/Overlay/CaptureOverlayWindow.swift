import AppKit

/// Borderless panel covering one screen — above the menu bar, the Dock and fullscreen apps —
/// that shows the frozen screen while the user picks an area or a window.
final class CaptureOverlayWindow: NSPanel {
    init(screen: NSScreen, view: CaptureOverlayView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = view
        // contentRect is relative to the main screen; setFrame takes global coordinates
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
