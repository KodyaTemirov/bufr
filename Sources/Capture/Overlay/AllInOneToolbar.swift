import AppKit
import SwiftUI

@MainActor @Observable
final class AllInOneToolbarModel {
    var windowMode = false
}

/// Mode bar shown over the frozen screen in all-in-one mode (⌘⇧5).
struct AllInOneToolbar: View {
    let model: AllInOneToolbarModel
    let onArea: () -> Void
    let onWindow: () -> Void
    let onFullscreen: () -> Void
    let onCancel: () -> Void
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            modeButton("rectangle.dashed", L10n("allInOne.area"), selected: !model.windowMode, action: onArea)
            modeButton("macwindow", L10n("allInOne.window"), selected: model.windowMode, action: onWindow)
            modeButton("display", L10n("allInOne.fullscreen"), selected: false, action: onFullscreen)

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            Button(L10n("common.cancel"), action: onCancel)
            Button(L10n("allInOne.capture"), action: onCapture)
                .buttonStyle(.borderedProminent)
                .disabled(model.windowMode)
        }
        .controlSize(.large)
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .padding(12)
    }

    private func modeButton(_ systemImage: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Non-activating panel above the capture overlays, so its buttons never take keyboard focus
/// from the overlay (arrows, Return and Esc keep working).
@MainActor
final class AllInOneToolbarPanel: NSPanel {
    init(rootView: some View, screen: NSScreen) {
        let hosting = NSHostingView(rootView: rootView)
        let size = hosting.fittingSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 60,
            width: size.width,
            height: size.height
        )
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        contentView = hosting
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
}
