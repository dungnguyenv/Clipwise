import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case redact
    case crop

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .redact: return "eye.slash"
        case .crop: return "crop"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .redact: return "Redact"
        case .crop: return "Crop"
        }
    }
}

/// One annotation drawn over the base image.
///
/// **All points and rects are in image pixel space with a top-left origin.**
/// Never store view coordinates here — that is what keeps annotations locked to
/// the image when the editor window is resized.
struct ImageAnnotation: Identifiable, Equatable {
    var id = UUID()
    var kind: Kind
    var color: Color
    var lineWidth: CGFloat

    enum Kind: Equatable {
        case stroke(points: [CGPoint], highlight: Bool)
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(String, origin: CGPoint, fontSize: CGFloat)
        case redact(CGRect)
    }
}
