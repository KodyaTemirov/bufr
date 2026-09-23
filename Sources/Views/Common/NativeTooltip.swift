import AppKit
import SwiftUI

extension View {
    /// An AppKit tooltip (`NSView.toolTip`) behind the view. Unlike `.help`, it goes through
    /// the regular AppKit mechanism, so a window's `allowsToolTipsWhenApplicationIsInactive`
    /// applies to it, and tests can see it.
    func tooltip(_ text: String) -> some View {
        background(NativeTooltip(text: text))
    }
}

private struct NativeTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = TooltipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.toolTip != text {
            view.toolTip = text
        }
    }
}

/// Only carries the tooltip; clicks go to the SwiftUI view on top.
private final class TooltipView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
