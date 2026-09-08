import AppKit
import Observation
import UniformTypeIdentifiers

/// State shared between the editor's views and the window that hosts them.
/// `EditorWindowController` reads `hasUnsavedChanges` to decide whether closing
/// needs a confirmation prompt.
@MainActor
@Observable
final class EditorSession {

    enum Mode {
        case text
        case image
    }

    let item: ClipboardItem
    let mode: Mode
    let document: ImageEditorDocument?

    var text: String
    var errorMessage: String?

    private let originalText: String
    private let editService: ItemEditService

    /// Returns `nil` when the item is not editable: a file URL, an image whose data
    /// failed to decode, or an RTF/HTML item with no plain-text representation to fall
    /// back to.
    init?(item: ClipboardItem, editService: ItemEditService) {
        self.item = item
        self.editService = editService

        switch item.primaryType {
        case .image:
            guard let image = item.image else { return nil }
            self.mode = .image
            self.document = ImageEditorDocument(baseImage: image)
            self.text = ""
            self.originalText = ""

        case .text, .rtf, .html:
            // RTF/HTML items open in plain-text mode: `ClipboardItem.isEditable` admits
            // them precisely because they usually carry a plain-text representation
            // alongside the rich one, and that's the representation the editor works
            // with. `hasRichTextRepresentation` (below) is what warns the user that
            // saving will drop the rich version.
            guard let existing = item.plainText else { return nil }
            self.mode = .text
            self.document = nil
            self.text = existing
            self.originalText = existing

        case .fileURL:
            return nil
        }
    }

    var hasUnsavedChanges: Bool {
        switch mode {
        case .text: return text != originalText
        case .image: return document?.hasUnsavedChanges ?? false
        }
    }

    /// Formats a text save (`ItemEditService.save(text:...)`) discards. Deliberately an
    /// explicit set, not everything that fails to conform to `.plainText` — that broader
    /// check also caught `public.url` and `public.vcard` (an ordinary link or contact
    /// copy), which have no formatted version to lose and put a "formatted version
    /// discarded" banner on some of the most common things anyone copies. A false-alarm
    /// banner is worse than the narrow, drift-prone set below: readers stop trusting it.
    /// If you're tempted to simplify this back to a `.plainText` conformance check,
    /// don't — that's the bug this set fixes. A genuinely new rich-text format does need
    /// adding here by hand; that's a conscious, bounded trade against crying wolf on
    /// every link copy.
    private static let richTextTypes: [UTType] = [.rtf, .rtfd, .flatRTFD, .html, .webArchive]

    /// True when the item carries a representation matching `richTextTypes` — checked by
    /// conformance, not exact-type equality, so vendor-specific subtypes of those five
    /// formats are still caught (that's the value conformance adds over a plain identifier
    /// list), while `public.url`, `public.vcard`, images, and arbitrary metadata stay out.
    var hasRichTextRepresentation: Bool {
        item.contents.contains { content in
            guard let type = UTType(content.type) else { return false }
            return Self.richTextTypes.contains { type.conforms(to: $0) }
        }
    }

    /// Returns `true` when the save succeeded and the window may close.
    /// On failure `errorMessage` is set for the alert.
    func save(_ target: ItemEditService.SaveMode) -> Bool {
        do {
            switch mode {
            case .text:
                try editService.save(text: text, for: item, mode: target)
            case .image:
                guard let image = document?.flattened() else {
                    errorMessage = "Could not render the edited image."
                    return false
                }
                try editService.save(image: image, for: item, mode: target)
            }
            return true
        } catch {
            // `ItemEditService.apply` rolls back its own mutation before rethrowing
            // `EditError.saveFailed`, so the in-memory `item` is already back in sync
            // with what's actually on disk by the time we get here — nothing else to
            // undo at this layer.
            errorMessage = error.localizedDescription
            return false
        }
    }
}
