import AppKit
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var numberOfCopies: Int
    var isPinned: Bool
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var contentHash: String  // SHA256 hash for duplicate detection

    @Relationship(deleteRule: .cascade, inverse: \ClipboardItemContent.item)
    var contents: [ClipboardItemContent] = []

    init(
        title: String,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String
    ) {
        self.id = UUID()
        self.title = title
        self.firstCopiedAt = Date()
        self.lastCopiedAt = Date()
        self.numberOfCopies = 1
        self.isPinned = false
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
    }

    // MARK: - Computed Properties

    var primaryType: ContentType {
        contents
            .compactMap { $0.contentType }
            .sorted { $0.displayPriority > $1.displayPriority }
            .first ?? .text
    }

    var plainText: String? {
        guard let content = contents.first(where: {
            $0.type == UTType.utf8PlainText.identifier || $0.type == UTType.plainText.identifier
        }), let data = content.value else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var image: NSImage? {
        guard let content = contents.first(where: {
            let utType = UTType($0.type) ?? .data
            return utType.conforms(to: .image)
        }), let data = content.value else { return nil }
        return NSImage(data: data)
    }

    var fileURLs: [URL] {
        contents
            .filter { $0.type == UTType.fileURL.identifier }
            .compactMap { content -> URL? in
                guard let data = content.value,
                      let urlString = String(data: data, encoding: .utf8)
                else { return nil }
                return URL(string: urlString)
            }
    }

    // MARK: - Password Detection

    /// Heuristic: detect if the text looks like a password/secret
    var looksLikePassword: Bool {
        guard let text = plainText else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must be single-line, no spaces, reasonable length
        let isSingleLine = !trimmed.contains(where: { $0.isNewline })
        let hasNoSpaces = !trimmed.contains(" ")
        let length = trimmed.count
        guard length >= 8, length <= 128, isSingleLine, hasNoSpaces else { return false }

        // Known secret prefixes — always sensitive
        let secretPrefixes = ["sk-", "pk-", "ghp_", "gho_", "ghs_", "xoxb-", "xoxp-", "eyJ", "AKIA"]
        if secretPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }

        // Exclude common non-password patterns
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return false }
        if lower.hasPrefix("ftp://") || lower.hasPrefix("ssh://") { return false }
        if lower.hasPrefix("file://") || lower.hasPrefix("mailto:") { return false }
        if lower.contains("@") && lower.contains(".") { return false } // email
        if lower.hasPrefix("/") || lower.hasPrefix("~") { return false } // file path
        if lower.hasSuffix(".com") || lower.hasSuffix(".org") || lower.hasSuffix(".io") ||
           lower.hasSuffix(".net") || lower.hasSuffix(".dev") || lower.hasSuffix(".app") { return false } // domain
        if lower.contains("localhost") { return false }

        // Require 3+ character classes AND high entropy (not just a simple word with punctuation)
        let hasUpper = trimmed.contains(where: { $0.isUppercase })
        let hasLower = trimmed.contains(where: { $0.isLowercase })
        let hasDigit = trimmed.contains(where: { $0.isNumber })
        let hasSymbol = trimmed.contains(where: { "!@#$%^&*()_+-=[]{}|;:',.<>?/~`\"\\".contains($0) })
        let classCount = [hasUpper, hasLower, hasDigit, hasSymbol].filter { $0 }.count

        // Need all 4 classes, or 3 classes with high digit/symbol ratio (random-looking)
        if classCount >= 4 { return true }
        if classCount >= 3 {
            let digitCount = trimmed.filter { $0.isNumber }.count
            let symbolCount = trimmed.filter { "!@#$%^&*()_+-=[]{}|;:',.<>?/~`\"\\".contains($0) }.count
            let randomRatio = Double(digitCount + symbolCount) / Double(length)
            return randomRatio >= 0.3
        }

        return false
    }

    // MARK: - Hash Generation

    static func generateHash(from pasteboardItems: [NSPasteboardItem]) -> String {
        var hasher = SHA256()
        for item in pasteboardItems {
            for type in item.types {
                if let data = item.data(forType: type) {
                    hasher.update(data: data)
                }
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func generateTitle(from pasteboardItems: [NSPasteboardItem]) -> String {
        for item in pasteboardItems {
            // Try plain text first
            if let text = item.string(forType: .string) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
                return String(firstLine.prefix(200))
            }
            // File URLs
            if let urlString = item.string(forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier)),
               let url = URL(string: urlString) {
                return url.lastPathComponent
            }
            // Image
            for type in item.types {
                if let utType = UTType(type.rawValue), utType.conforms(to: .image) {
                    return "Image"
                }
            }
        }
        return "Unknown"
    }

    // MARK: - Editing

    /// Only text and image items can be opened in the editor (v1).
    var isEditable: Bool {
        primaryType == .text || primaryType == .image
    }

    /// Hash for content assembled by the editor rather than read from a pasteboard.
    /// Same SHA256-hex format as `generateHash(from: [NSPasteboardItem])`.
    static func generateHash(from representations: [(type: String, data: Data)]) -> String {
        var hasher = SHA256()
        for representation in representations {
            hasher.update(data: representation.data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Title rule shared by capture and editing: first non-empty line, capped.
    static func generateTitle(forText text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return String(firstLine.prefix(Constants.maxTitleLength))
    }
}
