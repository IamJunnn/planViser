import Foundation
import AppKit

// MARK: - Tool Enum

enum CanvasTool: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case circle
    case line
    case textBox
    case eraser

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .textBox: return "textbox"
        case .eraser: return "eraser"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .line: return "Line"
        case .textBox: return "Text"
        case .eraser: return "Eraser"
        }
    }
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.red = c.redComponent
        self.green = c.greenComponent
        self.blue = c.blueComponent
        self.alpha = c.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static let black = CodableColor(nsColor: .black)
}

// MARK: - Shape Type

enum ShapeType: String, Codable {
    case rectangle
    case circle
    case line
}

// MARK: - Canvas Stroke

struct CanvasStroke: Codable, Equatable {
    var points: [CGPoint]
    var color: CodableColor
    var lineWidth: CGFloat

    static func == (lhs: CanvasStroke, rhs: CanvasStroke) -> Bool {
        lhs.points == rhs.points && lhs.color == rhs.color && lhs.lineWidth == rhs.lineWidth
    }
}

// MARK: - Canvas Shape

struct CanvasShape: Codable, Equatable {
    var shapeType: ShapeType
    var origin: CGPoint
    var size: CGSize
    var color: CodableColor
    var lineWidth: CGFloat
    var isFilled: Bool
}

// MARK: - Canvas Text Box

struct CanvasTextBox: Codable, Equatable {
    var text: String
    var origin: CGPoint
    var size: CGSize
    var fontSize: CGFloat
    var color: CodableColor
}

// MARK: - Canvas Document

struct CanvasDocument: Codable, Equatable {
    var strokes: [CanvasStroke]
    var shapes: [CanvasShape]
    var textBoxes: [CanvasTextBox]

    init() {
        self.strokes = []
        self.shapes = []
        self.textBoxes = []
    }
}

