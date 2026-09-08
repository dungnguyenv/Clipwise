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

    /// Heuristic: does this item's plain text look like a password or secret?
    /// The decision lives in the static `looksLikePassword(_:)` so it can be tested
    /// without a `ModelContext`; this just feeds it the plain-text representation.
    var looksLikePassword: Bool {
        guard let text = plainText else { return false }
        return Self.looksLikePassword(text)
    }

    /// Token prefixes that are secrets by construction, whatever the character-class
    /// rule below would say. This matters for vendors whose token bodies are
    /// lowercase+digits only (GitHub `ghp_`, GitLab `glpat-`, Hugging Face `hf_`, ...):
    /// that is two character classes, which the rule alone never flags. Checked after
    /// the shape guard (single line, no spaces, 8–128 chars) but before the exclusions,
    /// so `sk-...` still wins when its body happens to contain "@" or end in ".dev".
    private static let secretPrefixes: [String] = [
        // OpenAI / Anthropic / Stripe
        "sk-", "pk-", "sk_live_", "sk_test_", "rk_live_", "rk_test_",
        // GitHub / GitLab
        "ghp_", "gho_", "ghs_", "ghu_", "ghr_", "github_pat_", "glpat-",
        // Slack
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "xoxe-", "xapp-",
        // AWS / Google
        "AKIA", "AIza", "ya29.",
        // Package registries and model hubs
        "npm_", "pypi-", "hf_",
        // Misc SaaS
        "dop_v1_", "doo_v1_", "shpat_", "shpss_", "hvs.", "lin_api_", "PMAK-", "figd_", "sbp_",
        // JWT header (`{"alg":` base64url-encoded)
        "eyJ",
    ]

    /// Punctuation counted as the "symbol" character class. `@` and `.` are here even
    /// though they also drive the email/domain exclusions — those run first, so by the
    /// time this set is consulted the text is not an email or domain and its `@`/`.`
    /// legitimately count as randomness.
    private static let symbolCharacters: Set<Character> = Set("!@#$%^&*()_+-=[]{}|;:',.<>?/~`\"\\")

    /// Pure decision behind `looksLikePassword`. `PasswordDetectionTests` pins the
    /// shape each rule is meant to catch or let through; every exclusion below exists
    /// because it once produced a false positive, so don't drop one to "simplify".
    static func looksLikePassword(_ text: String) -> Bool {
        // PEM-armoured private keys are multi-line and contain spaces, so they have to
        // be recognised before the single-token shape guard rejects them.
        if isPEMPrivateKey(text) { return true }

        // Anything this large can't trim down to a ≤128-character token (it would need
        // over 1.5 KB of surrounding whitespace). Bail before the per-character scans:
        // `AppState.applySearch` runs this over every item on every keystroke, and the
        // history can hold multi-megabyte text.
        guard text.utf8.count <= 2_048 else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must be single-line, no spaces, reasonable length
        let isSingleLine = !trimmed.contains(where: { $0.isNewline })
        let hasNoSpaces = !trimmed.contains(" ")
        let length = trimmed.count
        guard length >= 8, length <= 128, isSingleLine, hasNoSpaces else { return false }

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
        let hasSymbol = trimmed.contains(where: { symbolCharacters.contains($0) })
        let classCount = [hasUpper, hasLower, hasDigit, hasSymbol].filter { $0 }.count

        // Need all 4 classes, or 3 classes with high digit/symbol ratio (random-looking)
        if classCount >= 4 { return true }
        if classCount >= 3 {
            let digitCount = trimmed.filter { $0.isNumber }.count
            let symbolCount = trimmed.filter { symbolCharacters.contains($0) }.count
            let randomRatio = Double(digitCount + symbolCount) / Double(length)
            return randomRatio >= 0.3
        }

        return false
    }

    /// `-----BEGIN … PRIVATE KEY-----` blocks: RSA/EC/OpenSSH keys and PGP
    /// "PRIVATE KEY BLOCK"s. Certificates and public keys share the armour but not the
    /// secrecy, which is why the match is on "PRIVATE KEY" rather than "-----BEGIN".
    /// The byte bound keeps the trim off multi-megabyte text; even an 8192-bit RSA key
    /// or a PGP block with subkeys stays far below it.
    private static func isPEMPrivateKey(_ text: String) -> Bool {
        guard text.utf8.count <= 16_384 else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("-----BEGIN ") && trimmed.contains("PRIVATE KEY")
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

    /// Images are editable outright. Everything else is editable when it has a plain-text
    /// representation to edit — except file items, which are never editable regardless of
    /// what else they carry: a file's "text" is just its path (see `fileURLs`), and a
    /// plain-text-encoded copy of that path isn't editable content either.
    ///
    /// This deliberately does not require `primaryType == .text`: content copied from a
    /// browser, Pages, Word, or Notes carries HTML or RTF alongside plain text, and
    /// `primaryType` reports whichever of those ranks highest — never `.text` when either
    /// is present. Gating on `primaryType == .text` would make most real-world rich text
    /// impossible to open in the editor, even though `EditorSession` opens it in `.text`
    /// mode (converting to plain text on save, which is exactly what `TextEditorPane`'s
    /// rich-text warning banner exists to flag before it happens).
    ///
    /// The file exclusion is checked directly against `contents` (`isFileItem`) rather
    /// than inferred from `primaryType != .fileURL`. `ContentType.displayPriority` — the
    /// thing that currently makes `.fileURL` outrank every other type in `primaryType` —
    /// is documented as a *display* preference, not an editability rule; deriving
    /// editability from it would make this silently wrong if that ranking is ever
    /// reordered for a display-only reason.
    var isEditable: Bool {
        Self.isEditable(primaryType: primaryType, isFileItem: isFileItem, hasPlainText: plainText != nil)
    }

    /// Pure decision behind `isEditable`, over the three inputs it actually depends on.
    /// `isEditable` itself can never exercise the `isFileItem == true` /
    /// `primaryType == .image` combination against a real `ClipboardItem`:
    /// `ContentType.displayPriority` currently ranks `.fileURL` above every other case,
    /// so any item that is a file item also has `primaryType == .fileURL`, never
    /// `.image` — that combination of inputs is simply unreachable through `contents`.
    /// Exposed as a static function precisely so a test can supply that unreachable
    /// combination directly and pin that the file guard runs first regardless — the
    /// thing no test built from a real item can demonstrate, because every real item
    /// that could reach the `primaryType == .image` branch already has `isFileItem ==
    /// false` by construction.
    static func isEditable(primaryType: ContentType, isFileItem: Bool, hasPlainText: Bool) -> Bool {
        guard !isFileItem else { return false }
        if primaryType == .image { return true }
        return hasPlainText
    }

    /// True when the item carries a file-URL representation. Kept separate from
    /// `primaryType` so `isEditable`'s file exclusion doesn't depend on
    /// `ContentType.displayPriority` ordering — see `isEditable`'s doc comment.
    private var isFileItem: Bool {
        contents.contains { $0.type == UTType.fileURL.identifier }
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
