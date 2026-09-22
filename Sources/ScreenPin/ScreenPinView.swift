import AppKit
import Carbon.HIToolbox

final class ScreenPinView: NSView {
    weak var panel: ScreenPinPanel?

    private let lockBadge = NSImageView()
    private var trackingArea: NSTrackingArea?

    init(image: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        setImage(image)

        lockBadge.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        lockBadge.contentTintColor = .white
        lockBadge.wantsLayer = true
        lockBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        lockBadge.layer?.cornerRadius = 10
        lockBadge.isHidden = true
        lockBadge.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        lockBadge.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(lockBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setImage(_ image: NSImage) {
        layer?.contents = image
    }

    func setLocked(_ locked: Bool) {
        lockBadge.isHidden = !locked
    }

    override func layout() {
        super.layout()
        lockBadge.frame.origin = CGPoint(x: bounds.maxX - 26, y: bounds.maxY - 26)
    }

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.borderWidth = 1.5
    }

    override func mouseExited(with event: NSEvent) {
        layer?.borderWidth = 0
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2, let panel {
            panel.manager?.edit(panel)
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 5)
        window.alphaValue = ScreenPinGeometry.opacity(window.alphaValue, scrollDelta: delta)
    }

    override func magnify(with event: NSEvent) {
        panel?.zoom(by: 1 + event.magnification)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let panel else { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case kVK_Escape:
            panel.manager?.close(panel)
        case kVK_ANSI_W where modifiers == .command:
            panel.manager?.close(panel)
        case kVK_ANSI_C where modifiers == .command:
            panel.manager?.copy(panel)
        case kVK_ANSI_0 where modifiers == .command:
            panel.resetSize()
        case kVK_ANSI_L where modifiers.isEmpty:
            panel.isLocked.toggle()
        case kVK_LeftArrow:
            panel.nudge(dx: -step, dy: 0)
        case kVK_RightArrow:
            panel.nudge(dx: step, dy: 0)
        case kVK_UpArrow:
            panel.nudge(dx: 0, dy: step)
        case kVK_DownArrow:
            panel.nudge(dx: 0, dy: -step)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(L10n("card.copy"), #selector(copyPin)))
        menu.addItem(item(L10n("card.saveAs"), #selector(saveAs)))
        if panel?.manager?.canEdit == true {
            menu.addItem(item(L10n("card.annotate"), #selector(edit)))
        }

        let opacity = NSMenuItem(title: L10n("screenPin.opacity"), action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for percent in [100, 75, 50, 25] {
            let entry = item("\(percent)%", #selector(setOpacity(_:)))
            entry.tag = percent
            entry.state = Int(((window?.alphaValue ?? 1) * 100).rounded()) == percent ? .on : .off
            opacityMenu.addItem(entry)
        }
        opacity.submenu = opacityMenu
        menu.addItem(opacity)

        menu.addItem(item(L10n("screenPin.lock"), #selector(lock)))
        menu.addItem(item(L10n("screenPin.resetSize"), #selector(resetSize)))
        menu.addItem(.separator())
        menu.addItem(item(L10n("common.close"), #selector(closePin)))
        menu.addItem(item(L10n("screenPin.closeAll"), #selector(closeAll)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func copyPin() {
        guard let panel else { return }
        panel.manager?.copy(panel)
    }

    @objc private func saveAs() {
        guard let item = panel?.item else { return }
        Task { await ImageExporter.saveAs(item) }
    }

    @objc private func edit() {
        guard let panel else { return }
        panel.manager?.edit(panel)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        window?.alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func lock() {
        panel?.isLocked = true
    }

    @objc private func resetSize() {
        panel?.resetSize()
    }

    @objc private func closePin() {
        guard let panel else { return }
        panel.manager?.close(panel)
    }

    @objc private func closeAll() {
        panel?.manager?.closeAll()
    }
}
