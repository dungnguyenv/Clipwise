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

        // Single-line, no spaces, reasonable length → likely a password/token
        let isSingleLine = !trimmed.contains(where: { $0.isNewline })
        let hasNoSpaces = !trimmed.contains(" ")
        let length = trimmed.count

        // Too short or too long → not a password
        guard length >= 8, length <= 128 else { return false }
        guard isSingleLine, hasNoSpaces else { return false }

        // Check for mixed character classes (letters + digits + symbols)
        let hasUpper = trimmed.contains(where: { $0.isUppercase })
        let hasLower = trimmed.contains(where: { $0.isLowercase })
        let hasDigit = trimmed.contains(where: { $0.isNumber })
        let hasSymbol = trimmed.contains(where: { "!@#$%^&*()_+-=[]{}|;:',.<>?/~`\"\\".contains($0) })

        let classCount = [hasUpper, hasLower, hasDigit, hasSymbol].filter { $0 }.count

        // 3+ character classes and no common word patterns → likely password
        if classCount >= 3 { return true }

        // Common secret prefixes (API keys, tokens)
        let prefixes = ["sk-", "pk-", "ghp_", "gho_", "xoxb-", "xoxp-", "Bearer ", "eyJ"]
        if prefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }

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
}
