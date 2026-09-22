import AppKit
import SwiftUI

/// Scrollable, zoomable (pinch, ⌘+/⌘−) stage: the base image as a static layer with the
/// annotation canvas on top. The document view's frame is the image's point size while its
/// bounds are pixels, so both subviews work in base-image pixels.
struct EditorCanvasContainer: NSViewRepresentable {
    let model: EditorViewModel
    let onCommand: (EditorCommand) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let pixelSize = CGSize(width: model.document.pixelWidth, height: model.document.pixelHeight)
        let pointSize = CGSize(width: pixelSize.width / model.document.pointScale, height: pixelSize.height / model.document.pointScale)

        let stage = FlippedView(frame: CGRect(origin: .zero, size: pointSize))
        stage.bounds = CGRect(origin: .zero, size: pixelSize)

        let baseView = BaseImageView(image: model.base)
        baseView.frame = stage.bounds
        stage.addSubview(baseView)

        let canvas = AnnotationCanvasView(model: model)
        canvas.frame = stage.bounds
        canvas.onCommand = onCommand
        stage.addSubview(canvas)

        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = stage
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true

        context.coordinator.scrollView = scrollView
        context.coordinator.canvas = canvas
        DispatchQueue.main.async {
            context.coordinator.zoomToFit()
            canvas.window?.makeFirstResponder(canvas)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var canvas: AnnotationCanvasView?

        /// Whole image visible, never enlarged beyond 100% of its point size.
        func zoomToFit() {
            guard let scrollView, let document = scrollView.documentView else { return }
            let available = scrollView.contentView.bounds.size
            let content = document.frame.size
            guard content.width > 0, content.height > 0, available.width > 0 else { return }
            let scale = min(1, (available.width - 24) / content.width, (available.height - 24) / content.height)
            scrollView.magnification = max(scrollView.minMagnification, scale)
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The untouched base image, drawn once as layer contents (never redrawn while editing).
private final class BaseImageView: NSView {
    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest // crisp pixels when zoomed in
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
}

/// Keeps a document smaller than the viewport in the middle instead of the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let documentFrame = documentView.frame
        if rect.width > documentFrame.width {
            rect.origin.x = documentFrame.midX - rect.width / 2
        }
        if rect.height > documentFrame.height {
            rect.origin.y = documentFrame.midY - rect.height / 2
        }
        return rect
    }
}
