import AppKit
import Observation

/// The editor's state and every editing operation. The canvas only forwards pointer and key
/// events here and draws `renderDocument`; all geometry is in base-image pixels.
@MainActor @Observable
final class EditorViewModel {
    enum Weight: CaseIterable {
        case thin, medium, thick

        var lineWidthPoints: Double {
            switch self {
            case .thin: 2
            case .medium: 4
            case .thick: 7
            }
        }

        var fontSizePoints: Double {
            switch self {
            case .thin: 18
            case .medium: 26
            case .thick: 38
            }
        }
    }

    private enum Drag {
        case create(start: CGPoint)
        case move(start: CGPoint, snapshot: AnnotationDocument)
        case resize(id: UUID, handle: AnnotationGeometry.Handle, snapshot: AnnotationDocument)
    }

    private(set) var document: AnnotationDocument
    let base: CGImage

    var tool: AnnotationTool = .arrow {
        didSet {
            if tool != .select { selection = [] }
            draft = nil
        }
    }
    var color: RGBAColor = .red {
        didSet {
            let color = color
            restyleSelection { $0.color = color }
        }
    }
    var weight: Weight = .medium {
        didSet {
            let lineWidth = weight.lineWidthPoints * document.pointScale
            let fontSize = weight.fontSizePoints * document.pointScale
            restyleSelection {
                $0.lineWidth = lineWidth
                $0.fontSize = fontSize
            }
        }
    }
    var selection: Set<UUID> = []
    /// The annotation being drawn; shown on top until the pointer is released
    private(set) var draft: Annotation?
    private(set) var editingTextID: UUID?
    /// The document as last saved; anything else (including an edit made while a save was
    /// running) is unsaved
    private var savedDocument: AnnotationDocument
    var isDirty: Bool { document != savedDocument }
    /// Hit radius in pixels; the canvas updates it with the zoom level
    var hitTolerance: CGFloat = 8

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private var drag: Drag?

    init(document: AnnotationDocument, base: CGImage) {
        self.document = document
        self.savedDocument = document
        self.base = base
        undoManager.groupsByEvent = false
    }

    /// What the canvas draws: the document plus the shape being drawn.
    var renderDocument: AnnotationDocument {
        var rendered = document
        if let draft { rendered.annotations.append(draft) }
        return rendered
    }

    var currentStyle: AnnotationStyle {
        AnnotationStyle(
            color: color,
            lineWidth: weight.lineWidthPoints * document.pointScale,
            fontSize: weight.fontSizePoints * document.pointScale
        )
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    /// `document` is what was written, which may be older than the current one.
    func markSaved(_ document: AnnotationDocument) {
        savedDocument = document
    }

    // MARK: - Pointer

    func pointerDown(at point: CGPoint, shift: Bool, clickCount: Int) {
        switch tool {
        case .select:
            beginSelectDrag(at: point, shift: shift, clickCount: clickCount)

        case .counter:
            let counter = Annotation(shape: .counter(center: point, number: document.nextCounterNumber), style: currentStyle)
            change { $0.add(counter) }

        case .text:
            if let existing = document.topmost(at: point, tolerance: hitTolerance), case .text = existing.shape {
                editingTextID = existing.id
                selection = [existing.id]
                return
            }
            let annotation = Annotation(shape: .text(origin: point, string: ""), style: currentStyle)
            // Added without an undo step; finishing the edit records it
            document.add(annotation)
            editingTextID = annotation.id

        default:
            drag = .create(start: point)
            draft = Annotation(shape: initialShape(for: tool, at: point), style: currentStyle)
        }
    }

    func pointerDragged(to point: CGPoint, shift: Bool) {
        switch drag {
        case let .create(start):
            guard var current = draft else { return }
            current.shape = shape(for: tool, from: start, to: point, shift: shift, previous: current.shape)
            draft = current

        case let .move(start, snapshot):
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            var moved = snapshot
            for index in moved.annotations.indices where selection.contains(moved.annotations[index].id) {
                moved.annotations[index].shape = AnnotationGeometry.moved(moved.annotations[index].shape, by: delta)
            }
            document = moved

        case let .resize(id, handle, snapshot):
            var resized = snapshot
            guard let index = resized.annotations.firstIndex(where: { $0.id == id }) else { return }
            var target = point
            if shift, case let .arrow(start, end) = resized.annotations[index].shape {
                target = AnnotationGeometry.snappedEnd(from: handle == .end ? start : end, to: point)
            }
            resized.annotations[index].shape = AnnotationGeometry.resized(
                resized.annotations[index].shape, handle: handle, to: target, minimumSize: 4
            )
            document = resized

        case nil:
            break
        }
    }

    func pointerUp(at point: CGPoint) {
        defer { drag = nil }
        switch drag {
        case .create:
            guard let finished = draft else { return }
            draft = nil
            guard isMeaningful(finished.shape) else { return }
            if case let .spotlight(rect) = finished.shape, tool == .crop {
                let bounds = CGRect(x: 0, y: 0, width: document.pixelWidth, height: document.pixelHeight)
                change { $0.crop = rect.standardized.integral.intersection(bounds) }
                tool = .select
                return
            }
            change { $0.add(finished) }
            selection = [finished.id]

        case let .move(_, snapshot), let .resize(_, _, snapshot):
            if snapshot != document {
                registerUndo(restoring: snapshot)
            }

        case nil:
            break
        }
    }

    // MARK: - Text

    func finishEditingText(id: UUID, string: String) {
        editingTextID = nil
        guard let index = document.annotations.firstIndex(where: { $0.id == id }),
              case let .text(origin, previous) = document.annotations[index].shape
        else { return }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if previous.isEmpty {
                document.remove(ids: [id]) // never recorded, nothing to undo
            } else {
                change { $0.remove(ids: [id]) }
            }
            selection.remove(id)
            return
        }
        guard string != previous else { return }

        if previous.isEmpty {
            // First text for a freshly placed box: record it as one "add" step
            var before = document
            before.remove(ids: [id])
            document.annotations[index].shape = .text(origin: origin, string: string)
            registerUndo(restoring: before)
        } else {
            change { $0.annotations[index].shape = .text(origin: origin, string: string) }
        }
    }

    // MARK: - Commands

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        change { $0.remove(ids: ids) }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        let offset = 12 * document.pointScale
        var copies: [UUID] = []
        change { copies = $0.duplicate(ids: ids, offset: offset) }
        selection = Set(copies)
    }

    func selectAll() {
        tool = .select
        selection = Set(document.annotations.map(\.id))
    }

    /// Arrow keys: one point (⇧ ten) in image pixels.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard !selection.isEmpty else { return }
        let ids = selection
        let delta = CGSize(width: dx * document.pointScale, height: dy * document.pointScale)
        change { document in
            for index in document.annotations.indices where ids.contains(document.annotations[index].id) {
                document.annotations[index].shape = AnnotationGeometry.moved(document.annotations[index].shape, by: delta)
            }
        }
    }

    func resetCrop() {
        guard document.crop != nil else { return }
        change { $0.crop = nil }
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
    }

    // MARK: - Undo plumbing

    /// Applies a change to the document as one undo step.
    private func change(_ body: (inout AnnotationDocument) -> Void) {
        let before = document
        body(&document)
        guard before != document else { return }
        registerUndo(restoring: before)
    }

    private func registerUndo(restoring previous: AnnotationDocument) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(previous)
            }
        }
        undoManager.endUndoGrouping()
    }

    private func restore(_ previous: AnnotationDocument) {
        let current = document
        document = previous
        let ids = Set(previous.annotations.map(\.id))
        selection = selection.intersection(ids)
        // Registering while undoing makes this the redo step
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(current)
            }
        }
    }

    // MARK: - Helpers

    private func beginSelectDrag(at point: CGPoint, shift: Bool, clickCount: Int) {
        // Handles of a single selected annotation come first
        if selection.count == 1, let id = selection.first,
           let annotation = document.annotations.first(where: { $0.id == id }),
           let hit = AnnotationGeometry.handles(for: annotation.shape)
               .first(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= hitTolerance * 1.5 }) {
            drag = .resize(id: id, handle: hit.handle, snapshot: document)
            return
        }

        guard let hit = document.topmost(at: point, tolerance: hitTolerance) else {
            if !shift { selection = [] }
            return
        }
        if clickCount == 2, case .text = hit.shape {
            editingTextID = hit.id
            selection = [hit.id]
            return
        }
        if shift {
            if selection.contains(hit.id) { selection.remove(hit.id) } else { selection.insert(hit.id) }
        } else if !selection.contains(hit.id) {
            selection = [hit.id]
        }
        drag = .move(start: point, snapshot: document)
    }

    private func initialShape(for tool: AnnotationTool, at point: CGPoint) -> AnnotationShape {
        let empty = CGRect(origin: point, size: .zero)
        switch tool {
        case .arrow: return .arrow(start: point, end: point)
        case .line: return .line(start: point, end: point)
        case .rectangle: return .rectangle(empty)
        case .filledRectangle: return .filledRectangle(empty)
        case .ellipse: return .ellipse(empty)
        case .highlighter: return .highlighter(empty)
        case .pencil: return .pencil([point])
        case .pixelate: return .pixelate(empty)
        case .blur: return .blur(empty)
        case .spotlight, .crop: return .spotlight(empty) // crop reuses the rect drag
        case .select, .text, .counter: return .rectangle(empty)
        }
    }

    private func shape(for tool: AnnotationTool, from start: CGPoint, to point: CGPoint, shift: Bool, previous: AnnotationShape) -> AnnotationShape {
        let bounds = CGRect(x: 0, y: 0, width: document.pixelWidth, height: document.pixelHeight)
        let rect = SelectionGeometry.rect(from: start, to: point, square: shift, fromCenter: false, bounds: bounds)
        switch tool {
        case .arrow: return .arrow(start: start, end: shift ? AnnotationGeometry.snappedEnd(from: start, to: point) : point)
        case .line: return .line(start: start, end: shift ? AnnotationGeometry.snappedEnd(from: start, to: point) : point)
        case .rectangle: return .rectangle(rect)
        case .filledRectangle: return .filledRectangle(rect)
        case .ellipse: return .ellipse(rect)
        case .highlighter: return .highlighter(rect)
        case .pixelate: return .pixelate(rect)
        case .blur: return .blur(rect)
        case .spotlight, .crop: return .spotlight(rect)
        case .pencil:
            if case let .pencil(points) = previous { return .pencil(points + [point]) }
            return .pencil([start, point])
        case .select, .text, .counter: return previous
        }
    }

    /// Accidental clicks with a drawing tool add nothing.
    private func isMeaningful(_ shape: AnnotationShape) -> Bool {
        let minimum: CGFloat = 3
        switch shape {
        case let .arrow(start, end), let .line(start, end):
            return hypot(end.x - start.x, end.y - start.y) >= minimum * 2
        case let .pencil(points):
            return points.count >= 2
        default:
            guard let rect = AnnotationGeometry.rect(of: shape) else { return true }
            return rect.width >= minimum && rect.height >= minimum
        }
    }

    /// Changes only the attribute the user picked: a colour keeps each shape's thickness.
    private func restyleSelection(_ update: (inout AnnotationStyle) -> Void) {
        guard !selection.isEmpty else { return }
        let ids = selection
        change { document in
            for index in document.annotations.indices where ids.contains(document.annotations[index].id) {
                update(&document.annotations[index].style)
            }
        }
    }
}
