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

    /// True when the item carries a representation that a text save
    /// (`ItemEditService.save(text:...)`) will not write back — RTF, HTML, and formats
    /// that don't even classify under `ContentType` (RTFD/flat-RTFD, webarchive) all
    /// qualify.
    ///
    /// Checked by conformance to `.plainText` rather than by matching `.rtf`/`.html`
    /// specifically. Matching those two only would miss e.g. `com.apple.rtfd` or
    /// `com.apple.webarchive` — neither conforms to `.rtf` or `.html`, so
    /// `ContentType.classify` returns `nil` for them and `primaryType` falls through to
    /// `.text` — which is exactly the case where losing them silently would hurt most:
    /// TextEdit/Notes items with an inline attachment, or a full webarchive copy, open
    /// with no warning and a save would destroy the formatted version outright.
    /// Conformance to `.plainText` also correctly excludes legacy plain-text aliases
    /// (e.g. `com.apple.traditional-mac-plain-text`), which do conform and are exactly
    /// what a text save preserves — matching identifiers instead of conformance here
    /// would have raised a false banner for those.
    var hasRichTextRepresentation: Bool {
        item.contents.contains { content in
            guard let type = UTType(content.type) else { return false }
            return !type.conforms(to: .plainText)
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
