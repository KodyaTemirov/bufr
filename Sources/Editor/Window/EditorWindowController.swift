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

    var hasUnsavedChanges: Bool { model.isDirty }

    private let model: EditorViewModel
    private let store: AnnotationStore
    private let pins: ScreenPinManager
    private var allowsClose = false
    /// Saves run one after another: two overlapping saves could interleave their file writes
    private var lastSave: Task<ClipItem?, Never>?

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
            done: { [weak self] in self?.finish() },
            reveal: item.savedFilePath == nil ? nil : { [weak self] in self?.revealInFinder() },
            shareFilename: ImageExporter.suggestedFilename(for: item)
        )
        window.contentViewController = NSHostingController(rootView: EditorRootView(model: model, actions: actions))
        window.title = L10n("editor.title", item.displayTitle)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(Self.initialContentSize(for: session.document))
        window.contentMinSize = EditorRootView.minimumSize
        window.center()
    }

    /// The image at 100% of its point size when it fits, else shrunk to 80% of the screen.
    private static func initialContentSize(for document: AnnotationDocument) -> CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let toolbar = EditorRootView.toolbarHeight
        let image = CGSize(width: Double(document.pixelWidth) / document.pointScale + 48,
                           height: Double(document.pixelHeight) / document.pointScale + 48 + toolbar)
        let minimum = EditorRootView.minimumSize
        return CGSize(
            width: max(minimum.width, min(image.width, visible.width * 0.8)),
            height: max(minimum.height, min(image.height, visible.height * 0.8))
        )
    }

    // MARK: - Actions

    @discardableResult
    func save() async -> ClipItem? {
        commitPendingEdits()
        let previous = lastSave
        let task = Task { () -> ClipItem? in
            _ = await previous?.value
            return await self.performSave()
        }
        lastSave = task
        return await task.value
    }

    private func performSave() async -> ClipItem? {
        guard model.isDirty || item.annotationPath == nil && !model.document.annotations.isEmpty else { return item }
        let document = model.document
        do {
            item = try await store.commit(document, base: model.base, for: item)
            model.markSaved(document)
            return item
        } catch AnnotationStore.StoreError.changedElsewhere {
            showChangedElsewhereAlert()
            return nil
        } catch {
            logger.error("Saving annotations failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return nil
        }
    }

    /// A text box being typed in is part of the document only once typing ends; every action
    /// that saves, copies or closes ends it first (Done's ⌘↩ reaches the button before the
    /// text view).
    private func commitPendingEdits() {
        if let textEditor = window.firstResponder as? TextAnnotationEditor {
            textEditor.onFinish()
        }
    }

    private func showChangedElsewhereAlert() {
        let alert = NSAlert()
        alert.messageText = L10n("editor.changedElsewhere.title")
        alert.informativeText = L10n("editor.changedElsewhere.message")
        alert.beginSheetModal(for: window)
    }

    private func finish() {
        commitPendingEdits()
        Task {
            if model.isDirty {
                guard await save() != nil else { return }
            }
            allowsClose = true
            window.close()
        }
    }

    private func copyResult() {
        commitPendingEdits()
        guard let flattened = AnnotationRenderer.renderFlattened(model.document, base: model.base),
              let png = ImageEncoder.pngData(from: flattened, pointScale: CGFloat(model.document.pointScale), downscaleToOneX: false)
        else {
            NSSound.beep()
            return
        }
        PasteboardWriter.writeImage(png: png)
        ToastPresenter.show(L10n("toast.copied"))
    }

    /// The screenshots-folder copy; saved first, so the file has the edits.
    var canRevealInFinder: Bool { item.savedFilePath != nil }

    private func revealInFinder() {
        commitPendingEdits()
        Task {
            if model.isDirty {
                guard await save() != nil else { return }
            }
            guard let path = item.savedFilePath, FileManager.default.fileExists(atPath: path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
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
        commitPendingEdits()
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
    private let present: @MainActor (NSWindow) -> Void

    init(store: AnnotationStore, pins: ScreenPinManager, present: @escaping @MainActor (NSWindow) -> Void = { AppActivation.present($0) }) {
        self.store = store
        self.pins = pins
        self.present = present
    }

    /// Before quitting: false (quit cancelled) when an editor has unsaved changes; that editor
    /// comes forward and asks "Save changes?" instead.
    func reviewUnsavedChangesBeforeQuit() -> Bool {
        guard let unsaved = controllers.values.first(where: \.hasUnsavedChanges) else { return true }
        present(unsaved.window)
        unsaved.window.performClose(nil)
        return false
    }

    func open(_ item: ClipItem) {
        if let existing = controllers[item.id] {
            present(existing.window)
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
                present(controller.window)
            } catch {
                logger.error("Opening the editor failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }
}
