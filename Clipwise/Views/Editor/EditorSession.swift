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

    /// Returns `nil` when the item is not editable (file URLs, or an image whose
    /// data failed to decode).
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

        case .text:
            let existing = item.plainText ?? ""
            self.mode = .text
            self.document = nil
            self.text = existing
            self.originalText = existing

        case .fileURL, .rtf, .html:
            return nil
        }
    }

    var hasUnsavedChanges: Bool {
        switch mode {
        case .text: return text != originalText
        case .image: return document?.hasUnsavedChanges ?? false
        }
    }

    /// True when the item carries RTF or HTML that a text save will discard.
    var hasRichTextRepresentation: Bool {
        item.contents.contains { content in
            guard let type = UTType(content.type) else { return false }
            return type.conforms(to: .rtf) || type.conforms(to: .html)
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
            // `ItemEditService.apply` already mutated `item` (or inserted the
            // copy) before the save that just failed. Roll back so the in-memory
            // model matches what's actually on disk — otherwise the clipboard
            // panel behind this window would show the new title/content for an
            // edit that never persisted.
            editService.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
