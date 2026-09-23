import AppKit
import SwiftUI

/// The dashed frame around the recorded region and the controls next to it. Neither takes
/// the mouse or keyboard from the app being scrolled, and neither is in the frames (the
/// stream leaves Bufr's windows out).
@MainActor
final class ScrollingCapturePanels {
    private let framePanel: NSPanel
    private let controlsPanel: NSPanel

    init(
        region: ScrollRegion,
        model: ScrollingCaptureModel,
        onAuto: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenAccessibility: @escaping () -> Void
    ) {
        let regionRect = region.cocoaRect
        framePanel = Self.makePanel(frame: regionRect.insetBy(dx: -4, dy: -4))
        framePanel.ignoresMouseEvents = true
        framePanel.contentView = DashedFrameView()

        let controls = ScrollingCaptureControls(
            model: model, onAuto: onAuto, onDone: onDone, onCancel: onCancel, onOpenAccessibility: onOpenAccessibility
        )
        let hosting = NSHostingView(rootView: controls)
        let size = hosting.fittingSize
        let visible = NSScreen.screens.first { $0.frame.intersects(regionRect) }?.visibleFrame ?? region.screenFrame
        controlsPanel = Self.makePanel(frame: Self.controlsFrame(size: size, region: regionRect, visible: visible))
        controlsPanel.contentView = hosting
    }

    func show() {
        framePanel.orderFrontRegardless()
        controlsPanel.orderFrontRegardless()
    }

    func close() {
        framePanel.orderOut(nil)
        controlsPanel.orderOut(nil)
    }

    /// Below the region, else above it, else in the bottom-right corner of the screen.
    private static func controlsFrame(size: CGSize, region: CGRect, visible: CGRect) -> CGRect {
        let gap: CGFloat = 8
        let x = min(max(region.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        if region.minY - gap - size.height >= visible.minY {
            return CGRect(x: x, y: region.minY - gap - size.height, width: size.width, height: size.height)
        }
        if region.maxY + gap + size.height <= visible.maxY {
            return CGRect(x: x, y: region.maxY + gap, width: size.width, height: size.height)
        }
        return CGRect(x: visible.maxX - size.width, y: visible.minY, width: size.width, height: size.height)
    }

    private static func makePanel(frame: CGRect) -> NSPanel {
        let panel = ScrollingCapturePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }
}

/// Clicks work without the panel ever taking the keyboard.
private final class ScrollingCapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private final class DashedFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

struct ScrollingCaptureControls: View {
    let model: ScrollingCaptureModel
    let onAuto: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void
    let onOpenAccessibility: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            previewThumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(sizeText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(hintText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if model.autoUnavailable {
                    Button(L10n("scrolling.autoNeedsAccessibility"), action: onOpenAccessibility)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            .frame(minWidth: 210, alignment: .leading)

            Button(action: onAuto) {
                Label(L10n("scrolling.auto"), systemImage: model.isAuto ? "pause.fill" : "play.fill")
            }
            Button(L10n("common.cancel"), action: onCancel)
            Button(L10n("common.done"), action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .padding(4)
    }

    private var previewThumbnail: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
            if let preview = model.preview {
                // The newest part: the bottom of the long image
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 64, alignment: .bottom)
                    .clipped()
            }
        }
        .frame(width: 44, height: 64)
        .clipShape(.rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
    }

    private var sizeText: String {
        guard model.pixelSize.width > 0 else { return "—" }
        return "\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height)) px"
    }

    private var hintText: String {
        switch model.hint {
        case .start: L10n("scrolling.hint.start")
        case .slower: L10n("scrolling.hint.slower")
        case .end: L10n("scrolling.hint.end")
        case .limit: L10n("scrolling.hint.limit")
        case .none: model.isAuto ? L10n("scrolling.hint.auto") : L10n("scrolling.hint.start")
        }
    }
}
