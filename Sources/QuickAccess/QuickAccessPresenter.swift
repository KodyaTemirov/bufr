import AppKit
import SwiftUI

/// What a Quick Access card can ask the app to do.
struct QuickAccessActions {
    var copy: (ClipItem) -> Void
    var pin: (QuickAccessEntry) -> Void
    var reveal: (ClipItem) -> Void
    var copyText: (ClipItem) -> Void
}

/// Shows the Quick Access stack in a corner of the screen where the capture happened.
/// The panel never takes focus from the app the user is working in.
@MainActor
final class QuickAccessPresenter {
    static let cardSize = CGSize(width: 220, height: 138)
    static let spacing: CGFloat = 10
    static let overflowHeight: CGFloat = 26
    static let margin: CGFloat = 16
    /// Room for the cards' shadow
    static let inset: CGFloat = 10

    private let controller: QuickAccessController
    private let settings: ScreenshotSettings
    private let actions: QuickAccessActions
    private var panel: NSPanel?
    private var screen: NSScreen?

    init(controller: QuickAccessController, settings: ScreenshotSettings, actions: QuickAccessActions) {
        self.controller = controller
        self.settings = settings
        self.actions = actions
        controller.onChange = { [weak self] in
            self?.layout()
        }
    }

    func show(_ entry: QuickAccessEntry) {
        screen = entry.sourceRect.flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        } ?? DisplayInfo.screenUnderMouse()
        controller.add(entry)
    }

    private func layout() {
        guard !controller.entries.isEmpty, let screen else {
            panel?.orderOut(nil)
            return
        }

        let count = CGFloat(controller.visibleEntries.count)
        var height = count * Self.cardSize.height + max(0, count - 1) * Self.spacing
        if controller.overflowCount > 0 {
            height += Self.overflowHeight + Self.spacing
        }
        let size = CGSize(width: Self.cardSize.width + Self.inset * 2, height: height + Self.inset * 2)

        let visible = screen.visibleFrame
        let x = settings.quickAccessPosition == .bottomLeft
            ? visible.minX + Self.margin - Self.inset
            : visible.maxX - Self.margin + Self.inset - size.width
        let frame = CGRect(x: x, y: visible.minY + Self.margin - Self.inset, width: size.width, height: size.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let hosting = NSHostingView(rootView: QuickAccessStackView(controller: controller, actions: actions))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}
