import AppKit

/// Screenshots pinned above all windows ("ScreenPin", not to be confused with favourite
/// history items or pinboards). Pins are not restored after a relaunch.
@MainActor @Observable
final class ScreenPinManager {
    private(set) var pins: [ScreenPinPanel] = []

    /// Copies an item the same way the rest of the app does (moves it to the top of history)
    @ObservationIgnored var onCopy: (ClipItem) -> Void = { _ in }
    /// Opens the annotation editor (M4); nil hides "Annotate"
    @ObservationIgnored var onEdit: ((ClipItem) -> Void)?

    var hasPins: Bool { !pins.isEmpty }
    var canEdit: Bool { onEdit != nil }

    /// Window IDs that captures must keep (pins are content the user chose to show)
    var windowIDs: [CGWindowID] {
        pins.map { CGWindowID($0.windowNumber) }
    }

    /// Pins an image item. `sourceRect` (Cocoa global) places it exactly where it was captured.
    func pin(_ item: ClipItem, sourceRect: CGRect? = nil) async {
        guard let path = item.imagePath,
              let image = await ImageStorage.shared.loadImage(filename: path)
        else {
            NSSound.beep()
            return
        }

        let screen = sourceRect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? DisplayInfo.screenUnderMouse()
        guard let screen else { return }

        let frame = ScreenPinGeometry.initialFrame(
            imageSize: image.size,
            sourceRect: sourceRect,
            mouse: NSEvent.mouseLocation,
            visibleFrame: screen.visibleFrame
        )
        let panel = ScreenPinPanel(item: item, image: image, frame: frame)
        panel.manager = self
        pins.append(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close(_ panel: ScreenPinPanel) {
        panel.orderOut(nil)
        panel.close()
        pins.removeAll { $0 === panel }
    }

    func closeAll() {
        for panel in pins {
            panel.orderOut(nil)
            panel.close()
        }
        pins = []
    }

    /// Locked pins ignore the mouse, so the menu bar is the way back
    func unlockAll() {
        pins.forEach { $0.isLocked = false }
    }

    func copy(_ panel: ScreenPinPanel) {
        onCopy(panel.item)
        ToastPresenter.show(L10n("toast.copied"))
    }

    func edit(_ panel: ScreenPinPanel) {
        onEdit?(panel.item)
    }

    /// Swaps in the edited image for every pin showing `item`.
    func refresh(_ item: ClipItem) async {
        guard pins.contains(where: { $0.item.id == item.id }),
              let path = item.imagePath,
              let image = await ImageStorage.shared.loadImage(filename: path)
        else { return }
        for panel in pins where panel.item.id == item.id {
            panel.update(item: item, image: image)
        }
    }
}
