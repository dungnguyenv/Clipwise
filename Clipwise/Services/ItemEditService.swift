import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Writes editor output back into clipboard history.
@MainActor
final class ItemEditService {

    enum SaveMode {
        /// Replace the existing item's content, keeping its identity.
        case overwrite
        /// Insert a new item, leaving the original untouched.
        case copy
    }

    enum EditError: LocalizedError {
        case encodingFailed
        case tooLarge(bytes: Int)
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Could not encode the edited content."
            case .tooLarge(let bytes):
                let actual = Double(bytes) / 1_000_000
                let limit = Constants.maxContentSize / 1_000_000
                return String(
                    format: "The edited content is %.1f MB, over the %d MB history limit.",
                    actual, limit
                )
            case .saveFailed(let underlying):
                return "Could not save the edited item: \(underlying.localizedDescription)"
            }
        }
    }

    private let storageManager: StorageManager

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
    }

    @discardableResult
    func save(text: String, for item: ClipboardItem, mode: SaveMode) throws -> ClipboardItem {
        let data = Data(text.utf8)
        guard data.count <= Constants.maxContentSize else { throw EditError.tooLarge(bytes: data.count) }
        // Rich-text representations are deliberately dropped: PasteService replays
        // every stored type, so a stale RTF blob would paste the pre-edit content.
        let representations = [
            (type: UTType.utf8PlainText.identifier, data: data),
            (type: UTType.plainText.identifier, data: data),
        ]
        return try apply(
            representations: representations,
            title: ClipboardItem.generateTitle(forText: text),
            to: item,
            mode: mode
        )
    }

    @discardableResult
    func save(image: NSImage, for item: ClipboardItem, mode: SaveMode) throws -> ClipboardItem {
        guard let png = image.pngData() else { throw EditError.encodingFailed }
        guard png.count <= Constants.maxContentSize else { throw EditError.tooLarge(bytes: png.count) }

        var representations = [(type: UTType.png.identifier, data: png)]
        // Some older apps only read TIFF off the pasteboard. Skip it silently
        // rather than failing the whole save when it blows the cap.
        if let tiff = image.tiffRepresentation, tiff.count <= Constants.maxContentSize {
            representations.append((type: UTType.tiff.identifier, data: tiff))
        }
        return try apply(representations: representations, title: "Image", to: item, mode: mode)
    }

    // MARK: - Private

    private func apply(
        representations: [(type: String, data: Data)],
        title: String,
        to item: ClipboardItem,
        mode: SaveMode
    ) throws -> ClipboardItem {
        let hash = ClipboardItem.generateHash(from: representations)
        let newContents = representations.map { ClipboardItemContent(type: $0.type, value: $0.data) }

        let target: ClipboardItem
        switch mode {
        case .overwrite:
            let stale = item.contents
            item.contents = newContents
            // Delete each content individually — delete(model:) does not cascade here.
            for content in stale {
                storageManager.context.delete(content)
            }
            item.title = title
            item.contentHash = hash
            item.lastCopiedAt = Date()
            target = item

        case .copy:
            let copy = ClipboardItem(
                title: title,
                sourceAppBundleID: item.sourceAppBundleID,
                sourceAppName: item.sourceAppName,
                contentHash: hash
            )
            copy.contents = newContents
            storageManager.context.insert(copy)
            target = copy
        }

        do {
            try storageManager.context.save()
        } catch {
            throw EditError.saveFailed(error)
        }
        return target
    }
}
