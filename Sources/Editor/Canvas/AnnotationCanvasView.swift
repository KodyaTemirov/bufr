import AppKit
import Carbon.HIToolbox

enum EditorCommand {
    case copy
    case save
    case done
}

/// Transparent drawing surface over the base image. Flipped, with bounds in base-image pixels,
/// so event locations and `AnnotationRenderer` share one coordinate system.
final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    let model: EditorViewModel
    var onCommand: (EditorCommand) -> Void = { _ in }

    private var effectCache: [UUID: (source: CGRect, patch: (image: CGImage, rect: CGRect))] = [:]
    private var textEditor: TextAnnotationEditor?

    init(model: EditorViewModel) {
        self.model = model
        super.init(frame: CGRect(x: 0, y: 0, width: model.document.pixelWidth, height: model.document.pixelHeight))
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Base-image pixels per screen point at the current zoom.
    private var pixelsPerScreenPoint: CGFloat {
        let onScreen = convert(CGSize(width: 1, height: 1), to: nil).width
        return onScreen > 0 ? 1 / onScreen : 1
    }

    // MARK: - Observation

    private func observeModel() {
        withObservationTracking {
            _ = model.renderDocument
            _ = model.selection
            _ = model.editingTextID
            _ = model.tool
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
                if self.model.editingTextID != nil, self.textEditor == nil {
                    self.beginTextEditing()
                }
                self.observeModel()
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var document = model.renderDocument
        if let editing = model.editingTextID {
            document.annotations.removeAll { $0.id == editing } // the text view shows it
        }

        AnnotationRenderer.draw(document, base: model.base, in: context, includeBase: false) { [weak self] annotation in
            self?.effectPatch(for: annotation)
        }

        drawCrop(document.crop, in: context)
        drawSelection(in: context)
    }

    private func effectPatch(for annotation: Annotation) -> (image: CGImage, rect: CGRect)? {
        guard let source = AnnotationGeometry.rect(of: annotation.shape) else { return nil }
        if let cached = effectCache[annotation.id], cached.source == source {
            return cached.patch
        }
        guard let patch = EffectRenderer.shared.patch(for: annotation.shape, base: model.base) else { return nil }
        effectCache[annotation.id] = (source, patch)
        return patch
    }

    private func drawCrop(_ crop: CGRect?, in context: CGContext) {
        guard let crop, model.tool != .crop else { return }
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(crop)
        context.saveGState()
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(pixelsPerScreenPoint)
        context.stroke(crop)
        context.restoreGState()
    }

    private func drawSelection(in context: CGContext) {
        let selected = model.document.annotations.filter { model.selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        let unit = pixelsPerScreenPoint

        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(unit)
        context.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
        for annotation in selected {
            context.stroke(AnnotationGeometry.bounds(of: annotation).insetBy(dx: -3 * unit, dy: -3 * unit))
        }
        context.restoreGState()

        guard selected.count == 1, let only = selected.first else { return }
        let size = 8 * unit
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(unit)
        for handle in AnnotationGeometry.handles(for: only.shape) {
            let rect = CGRect(x: handle.point.x - size / 2, y: handle.point.y - size / 2, width: size, height: size)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
        context.restoreGState()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: model.tool == .select ? .arrow : (model.tool == .text ? .iBeam : .crosshair))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if textEditor != nil {
            // A click outside the text box finishes typing and does nothing else
            window?.makeFirstResponder(self)
            return
        }
        window?.makeFirstResponder(self)
        model.hitTolerance = 6 * pixelsPerScreenPoint
        let point = convert(event.locationInWindow, from: nil)
        model.pointerDown(at: point, shift: event.modifierFlags.contains(.shift), clickCount: event.clickCount)
        if model.editingTextID != nil {
            beginTextEditing()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        model.pointerDragged(to: convert(event.locationInWindow, from: nil), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        model.pointerUp(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let characters = Self.shortcutCharacters(for: event)
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelection()
            return
        case kVK_Escape:
            if model.selection.isEmpty { model.tool = .select } else { model.selection = [] }
            return
        case kVK_LeftArrow: model.nudgeSelection(dx: -step, dy: 0); return
        case kVK_RightArrow: model.nudgeSelection(dx: step, dy: 0); return
        case kVK_UpArrow: model.nudgeSelection(dx: 0, dy: -step); return
        case kVK_DownArrow: model.nudgeSelection(dx: 0, dy: step); return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if modifiers == .command { onCommand(.done); return }
        default:
            break
        }

        if modifiers == .command {
            switch characters {
            case "d": model.duplicateSelection(); return
            case "a": model.selectAll(); return
            case "z": model.undo(); return
            case "c": onCommand(.copy); return
            case "s": onCommand(.save); return
            default: break
            }
        }
        if modifiers == [.command, .shift], characters == "z" {
            model.redo()
            return
        }

        if modifiers.isEmpty || modifiers == .shift, let character = characters.first {
            if let tool = AnnotationTool.forShortcut(character) {
                model.tool = tool
                return
            }
            if let digit = character.wholeNumberValue, (1...RGBAColor.palette.count).contains(digit) {
                model.color = RGBAColor.palette[digit - 1]
                return
            }
            if character == "[", let index = EditorViewModel.Weight.allCases.firstIndex(of: model.weight), index > 0 {
                model.weight = EditorViewModel.Weight.allCases[index - 1]
                return
            }
            if character == "]", let index = EditorViewModel.Weight.allCases.firstIndex(of: model.weight),
               index < EditorViewModel.Weight.allCases.count - 1 {
                model.weight = EditorViewModel.Weight.allCases[index + 1]
                return
            }
        }
        super.keyDown(with: event)
    }

    /// What the key means for shortcuts: the typed letter on Latin layouts (Dvorak, AZERTY),
    /// the letter at that key's US position on others (the key under V types "м" in Russian).
    private static func shortcutCharacters(for event: NSEvent) -> String {
        let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if !typed.isEmpty, typed.allSatisfy(\.isASCII) {
            return typed
        }
        return usPositions[Int(event.keyCode)].map(String.init) ?? typed
    }

    private static let usPositions: [Int: Character] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e",
        kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j",
        kVK_ANSI_K: "k", kVK_ANSI_L: "l", kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o",
        kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x", kVK_ANSI_Y: "y",
        kVK_ANSI_Z: "z", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
    ]

    // MARK: - Text editing

    private func beginTextEditing() {
        guard textEditor == nil,
              let id = model.editingTextID,
              let annotation = model.document.annotations.first(where: { $0.id == id }),
              case let .text(origin, string) = annotation.shape
        else { return }

        let editor = TextAnnotationEditor(textFrame: CGRect(origin: origin, size: AnnotationGeometry.textSize(string, style: annotation.style)))
        editor.font = AnnotationGeometry.textFont(size: annotation.style.fontSize)
        editor.textColor = NSColor(cgColor: annotation.style.color.cgColor)
        editor.insertionPointColor = NSColor(cgColor: annotation.style.color.cgColor) ?? .labelColor
        editor.string = string
        editor.delegate = self
        editor.onFinish = { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
        addSubview(editor)
        textEditor = editor
        window?.makeFirstResponder(editor)
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = textEditor, let id = model.editingTextID,
              let annotation = model.document.annotations.first(where: { $0.id == id })
        else { return }
        editor.setFrameSize(AnnotationGeometry.textSize(editor.string, style: annotation.style))
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let editor = textEditor, let id = model.editingTextID else { return }
        textEditor = nil
        editor.removeFromSuperview()
        model.finishEditingText(id: id, string: editor.string)
        needsDisplay = true
    }
}

/// Inline text box for text annotations: Esc or ⌘↩ finishes, like clicking elsewhere.
final class TextAnnotationEditor: NSTextView {
    var onFinish: () -> Void = {}

    /// Typing gets its own undo stack. The editor's manager takes explicit groups only, and
    /// typing registers undo outside a group — an exception on every keystroke.
    private let typingUndoManager = UndoManager()
    override var undoManager: UndoManager? { typingUndoManager }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    convenience init(textFrame frame: NSRect) {
        let container = NSTextContainer(size: CGSize(width: 100_000, height: 100_000))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        self.init(frame: frame, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure() {
        drawsBackground = false
        isRichText = false
        allowsUndo = true
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = true
    }

    override func cancelOperation(_ sender: Any?) {
        onFinish()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), Int(event.keyCode) == kVK_Return {
            onFinish()
            return
        }
        super.keyDown(with: event)
    }
}
