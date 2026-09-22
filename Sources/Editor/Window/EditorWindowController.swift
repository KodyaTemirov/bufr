import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.bufr.app", category: "Editor")

/// One annotation editor window for one history image.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private(set) var item: ClipItem
    let window: NSWindow
    var onClose: (UUID) -> Void = { _ in }

    private let model: EditorViewModel
    private let store: AnnotationStore
    private let pins: ScreenPinManager
    private var allowsClose = false

    init(item: ClipItem, session: AnnotationStore.Session, store: AnnotationStore, pins: ScreenPinManager) {
        self.item = item
        self.store = store
        self.pins = pins
        self.model = EditorViewModel(document: session.document, base: session.base)
        self.window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        let actions = EditorActions(
            copy: { [weak self] in self?.copyResult() },
            save: { [weak self] in Task { await self?.save() } },
            pin: { [weak self] in self?.pinResult() },
            done: { [weak self] in self?.finish() }
        )
        window.contentViewController = NSHostingController(rootView: EditorRootView(model: model, actions: actions))
        window.title = L10n("editor.title", item.displayTitle)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(Self.initialContentSize(for: session.document))
        window.contentMinSize = CGSize(width: 640, height: 420)
        window.center()
    }

    /// The image at 100% of its point size when it fits, else shrunk to 80% of the screen.
    private static func initialContentSize(for document: AnnotationDocument) -> CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let toolbar: CGFloat = 52
        let image = CGSize(width: Double(document.pixelWidth) / document.pointScale + 48,
                           height: Double(document.pixelHeight) / document.pointScale + 48 + toolbar)
        return CGSize(
            width: max(640, min(image.width, visible.width * 0.8)),
            height: max(420, min(image.height, visible.height * 0.8))
        )
    }

    // MARK: - Actions

    @discardableResult
    func save() async -> ClipItem? {
        guard model.isDirty || item.annotationPath == nil && !model.document.annotations.isEmpty else { return item }
        do {
            item = try await store.commit(model.document, base: model.base, for: item)
            model.markSaved()
            return item
        } catch {
            logger.error("Saving annotations failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return nil
        }
    }

    private func finish() {
        Task {
            if model.isDirty {
                guard await save() != nil else { return }
            }
            allowsClose = true
            window.close()
        }
    }

    private func copyResult() {
        guard let flattened = AnnotationRenderer.renderFlattened(model.document, base: model.base),
              let png = ImageEncoder.pngData(from: flattened, pointScale: CGFloat(model.document.pointScale), downscaleToOneX: false)
        else {
            NSSound.beep()
            return
        }
        PasteboardWriter.writeImage(png: png)
        ToastPresenter.show(L10n("toast.copied"))
    }

    private func pinResult() {
        Task {
            guard let saved = await save() else { return }
            await pins.pin(saved)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model.undoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !allowsClose else { return true }

        let alert = NSAlert()
        alert.messageText = L10n("editor.unsaved.title")
        alert.informativeText = L10n("editor.unsaved.message")
        alert.addButton(withTitle: L10n("common.save"))
        alert.addButton(withTitle: L10n("editor.unsaved.discard"))
        alert.addButton(withTitle: L10n("common.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    self.finish()
                case .alertSecondButtonReturn:
                    self.allowsClose = true
                    self.window.close()
                default:
                    break
                }
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onClose(item.id)
    }
}

/// Opens at most one editor window per history item.
@MainActor
final class EditorWindowManager {
    private var controllers: [UUID: EditorWindowController] = [:]
    private let store: AnnotationStore
    private let pins: ScreenPinManager

    init(store: AnnotationStore, pins: ScreenPinManager) {
        self.store = store
        self.pins = pins
    }

    func open(_ item: ClipItem) {
        if let existing = controllers[item.id] {
            AppActivation.present(existing.window)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await store.open(item)
                let controller = EditorWindowController(item: item, session: session, store: store, pins: pins)
                controller.onClose = { [weak self] id in
                    self?.controllers[id] = nil
                }
                controllers[item.id] = controller
                AppActivation.present(controller.window)
            } catch {
                logger.error("Opening the editor failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }
}
