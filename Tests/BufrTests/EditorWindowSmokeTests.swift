import AppKit
import Carbon.HIToolbox
import SwiftUI
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

    @MainActor
    private struct Editor {
        let controller: EditorWindowController
        let canvas: AnnotationCanvasView
        let clipStore: ClipItemStore
        let annotationStore: AnnotationStore
        let item: ClipItem

        func event(_ type: NSEvent.EventType, _ pixel: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: canvas.convert(pixel, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }

        func key(_ keyCode: Int, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: controller.window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
            )!
        }

        func click(at pixel: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, pixel))
            canvas.mouseUp(with: event(.leftMouseUp, pixel))
        }
    }

    private func makeEditor() async throws -> Editor {
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
        return Editor(controller: controller, canvas: canvas, clipStore: clipStore, annotationStore: annotationStore, item: item)
    }

    @Test func canvasMapsWindowEventsToImagePixels() async throws {
        let editor = try await makeEditor()
        let canvas = editor.canvas
        let controller = editor.controller
        let event = editor.event
        #expect(canvas.bounds.size == CGSize(width: 400, height: 300))

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

    /// Typing goes into a text box without errors (the text view must not share the
    /// editor's explicitly grouped undo manager).
    @Test func typingIntoATextBox() async throws {
        let editor = try await makeEditor()
        editor.canvas.model.tool = .text
        editor.click(at: CGPoint(x: 50, y: 50))
        let textView = try #require(editor.controller.window.firstResponder as? NSTextView)

        textView.insertText("Hi", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.controller.window.makeFirstResponder(editor.canvas)

        guard case let .text(_, string)? = editor.canvas.model.document.annotations.first?.shape else {
            Issue.record("no text annotation")
            return
        }
        #expect(string == "Hi")
        editor.controller.window.close()
    }

    /// ⌘↩ (Done) while typing saves the text instead of closing without it.
    @Test func doneWhileTypingSavesTheText() async throws {
        let editor = try await makeEditor()
        var closed = false
        editor.controller.onClose = { _ in closed = true }
        editor.canvas.model.tool = .text
        editor.click(at: CGPoint(x: 50, y: 50))
        let textView = try #require(editor.controller.window.firstResponder as? NSTextView)
        textView.insertText("Hi", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.controller.hasUnsavedChanges)

        _ = editor.controller.window.performKeyEquivalent(with: editor.key(kVK_Return, "\r", .command))
        for _ in 0..<60 where !closed {
            try await Task.sleep(for: .milliseconds(50))
        }

        let saved = try #require(try editor.clipStore.item(id: editor.item.id))
        let reopened = try await editor.annotationStore.open(saved)
        #expect(closed)
        #expect(reopened.document.annotations.map(\.shape) == [.text(origin: CGPoint(x: 50, y: 50), string: "Hi")])
    }

    /// Tool letters work on the Russian layout too (the key under V types "м").
    @Test func toolShortcutsFollowKeyPositionOnNonLatinLayouts() async throws {
        let editor = try await makeEditor()
        editor.canvas.model.tool = .arrow

        editor.canvas.keyDown(with: editor.key(kVK_ANSI_V, "м"))
        #expect(editor.canvas.model.tool == .select)

        editor.canvas.keyDown(with: editor.key(kVK_ANSI_R, "к"))
        #expect(editor.canvas.model.tool == .rectangle)
        editor.controller.window.close()
    }

    /// Every toolbar button, Done included, is visible at the smallest window size.
    @Test func toolbarFitsTheMinimumWindowWidth() async throws {
        let editor = try await makeEditor()
        editor.canvas.model.tool = .crop
        editor.canvas.mouseDown(with: editor.event(.leftMouseDown, CGPoint(x: 10, y: 10)))
        editor.canvas.mouseDragged(with: editor.event(.leftMouseDragged, CGPoint(x: 200, y: 200)))
        editor.canvas.mouseUp(with: editor.event(.leftMouseUp, CGPoint(x: 200, y: 200))) // shows "Reset Crop" too
        try await Task.sleep(for: .milliseconds(100))

        let root = NSHostingView(rootView: EditorToolbar(model: editor.canvas.model, actions: EditorActions(copy: {}, save: {}, pin: {}, done: {})))
        #expect(root.fittingSize.width <= editor.controller.window.contentMinSize.width, "toolbar \(root.fittingSize.width) pt")
        editor.controller.window.close()
    }

    /// Quitting Bufr with unsaved edits stops and asks in that editor instead of losing them.
    @Test func quitIsHeldBackByUnsavedEdits() async throws {
        let clipStore = ClipItemStore(database: try AppDatabase.makeEmpty())
        let storage = ImageStorage(baseDirectory: try TestSupport.makeTempDirectory())
        let png = try #require(ImageEncoder.pngData(from: TestImages.blank(width: 200, height: 100), pointScale: 1, downscaleToOneX: false))
        let item = try await ClipIngestor(store: clipStore, imageStorage: storage).ingestImage(.init(data: png, origin: .screenshot, deduplicate: false))
        var presented: [NSWindow] = []
        let manager = EditorWindowManager(store: AnnotationStore(store: clipStore, imageStorage: storage), pins: ScreenPinManager()) {
            presented.append($0)
        }

        manager.open(item)
        for _ in 0..<40 where presented.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        let window = try #require(presented.first)
        #expect(manager.reviewUnsavedChangesBeforeQuit())

        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let contentView = try #require(window.contentView)
        let canvas = try #require(findCanvas(in: contentView))
        canvas.model.tool = .filledRectangle
        canvas.model.pointerDown(at: CGPoint(x: 10, y: 10), shift: false, clickCount: 1)
        canvas.model.pointerDragged(to: CGPoint(x: 60, y: 60), shift: false)
        canvas.model.pointerUp(at: CGPoint(x: 60, y: 60))

        #expect(!manager.reviewUnsavedChangesBeforeQuit())
        window.close()
    }
}
