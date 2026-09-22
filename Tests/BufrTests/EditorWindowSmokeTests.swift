import AppKit
import Testing
@testable import Bufr

/// Builds the real editor window (off-screen) and draws through the canvas with synthetic
/// mouse events, checking the pixel coordinate mapping end to end.
@MainActor
struct EditorWindowSmokeTests {
    private func findCanvas(in view: NSView) -> AnnotationCanvasView? {
        if let canvas = view as? AnnotationCanvasView { return canvas }
        for subview in view.subviews {
            if let found = findCanvas(in: subview) { return found }
        }
        return nil
    }

    @Test func canvasMapsWindowEventsToImagePixels() async throws {
        let database = try AppDatabase.makeEmpty()
        let clipStore = ClipItemStore(database: database)
        let storage = ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        let png = try #require(ImageEncoder.pngData(from: TestImages.blank(width: 400, height: 300), pointScale: 2, downscaleToOneX: false))
        let item = try await ClipIngestor(store: clipStore, imageStorage: storage)
            .ingestImage(.init(data: png, origin: .screenshot, deduplicate: false))
        let annotationStore = AnnotationStore(store: clipStore, imageStorage: storage)
        let session = try await annotationStore.open(item)

        let controller = EditorWindowController(item: item, session: session, store: annotationStore, pins: ScreenPinManager())
        controller.window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300)) // let SwiftUI build the canvas
        controller.window.contentView?.layoutSubtreeIfNeeded()

        let contentView = try #require(controller.window.contentView)
        let canvas = try #require(findCanvas(in: contentView))
        #expect(canvas.bounds.size == CGSize(width: 400, height: 300))

        func event(_ type: NSEvent.EventType, _ pixel: CGPoint) -> NSEvent {
            let location = canvas.convert(pixel, to: nil)
            return NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }

        canvas.model.tool = .filledRectangle
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 40, y: 30)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 140, y: 90)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 140, y: 90)))

        guard case let .filledRectangle(rect)? = canvas.model.document.annotations.first?.shape else {
            Issue.record("no rectangle drawn")
            return
        }
        #expect(abs(rect.minX - 40) < 1.5 && abs(rect.minY - 30) < 1.5)
        #expect(abs(rect.width - 100) < 1.5 && abs(rect.height - 60) < 1.5)
        controller.window.close()
    }
}
