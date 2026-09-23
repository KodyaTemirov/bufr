import Foundation

enum AnnotationTool: String, CaseIterable, Sendable {
    case select
    case arrow
    case line
    case rectangle
    case filledRectangle
    case ellipse
    case text
    case highlighter
    case pencil
    case counter
    case pixelate
    case blur
    case spotlight
    case crop

    /// Single-key shortcut while not editing text
    var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .filledRectangle: "f"
        case .ellipse: "o"
        case .text: "t"
        case .highlighter: "h"
        case .pencil: "p"
        case .counter: "n"
        case .pixelate: "x"
        case .blur: "b"
        case .spotlight: "s"
        case .crop: "c"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .filledRectangle: "rectangle.fill"
        case .ellipse: "circle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .pencil: "pencil.tip"
        case .counter: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        case .spotlight: "light.max"
        case .crop: "crop"
        }
    }

    var titleKey: String { "editor.tool.\(rawValue)" }

    /// Toolbar order, split where a divider goes: selection, shapes, drawing and text, effects, crop.
    static let groups: [[AnnotationTool]] = [
        [.select],
        [.arrow, .line, .rectangle, .filledRectangle, .ellipse],
        [.text, .highlighter, .pencil, .counter],
        [.pixelate, .blur, .spotlight],
        [.crop],
    ]

    enum Option: Equatable, Sendable {
        case color
        /// Line width of strokes
        case thickness
        /// Font size of text and step numbers (the same weight setting)
        case size
    }

    /// What the options row offers for this tool: only settings that change what it draws.
    var options: [Option] {
        switch self {
        case .arrow, .line, .rectangle, .ellipse, .pencil: [.color, .thickness]
        case .filledRectangle, .highlighter: [.color]
        case .text, .counter: [.color, .size]
        case .select, .pixelate, .blur, .spotlight, .crop: []
        }
    }

    static func forShortcut(_ character: Character) -> AnnotationTool? {
        allCases.first { $0.shortcut == character }
    }
}
