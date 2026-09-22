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

    static func forShortcut(_ character: Character) -> AnnotationTool? {
        allCases.first { $0.shortcut == character }
    }
}
