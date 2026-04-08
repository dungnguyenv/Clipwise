import Foundation
import UniformTypeIdentifiers

enum ContentType: String, Codable, CaseIterable {
    case text
    case image
    case fileURL
    case rtf
    case html

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .fileURL: return "File"
        case .rtf: return "Rich Text"
        case .html: return "HTML"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .fileURL: return "doc"
        case .rtf: return "doc.richtext"
        case .html: return "globe"
        }
    }

    static func classify(_ utType: UTType) -> ContentType? {
        if utType.conforms(to: .fileURL) { return .fileURL }
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .rtf) { return .rtf }
        if utType.conforms(to: .html) { return .html }
        if utType.conforms(to: .plainText) { return .text }
        return nil
    }

    /// Priority order for display — higher priority types are preferred for preview
    var displayPriority: Int {
        switch self {
        case .fileURL: return 5
        case .image: return 4
        case .rtf: return 3
        case .html: return 2
        case .text: return 1
        }
    }
}
