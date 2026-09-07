import AppKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

@MainActor
final class ItemEditServiceTests: XCTestCase {

    private func makeStorage() -> StorageManager {
        StorageManager(inMemory: true)
    }

    private func makeTextItem(_ text: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(
            title: text,
            sourceAppBundleID: "com.example.source",
            sourceAppName: "Source",
            contentHash: "original-hash"
        )
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    private func makeImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    /// A large flat-colour bitmap, filled via the raw buffer rather than
    /// per-pixel `setColor` (which is far too slow at this size). TIFF stores
    /// this uncompressed (~width * height * 4 bytes), while PNG collapses a
    /// flat colour to almost nothing — the gap the TIFF-drop guard relies on.
    private func makeLargeSolidImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        if let buffer = rep.bitmapData {
            memset(buffer, 0xFF, rep.bytesPerRow * height)
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    func testOverwriteKeepsIdentityAndReplacesContent() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        item.isPinned = true
        let id = item.id
        let firstCopiedAt = item.firstCopiedAt
        let numberOfCopies = item.numberOfCopies
        let sourceAppBundleID = item.sourceAppBundleID
        let sourceAppName = item.sourceAppName

        try service.save(text: "after", for: item, mode: .overwrite)

        XCTAssertEqual(item.id, id)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.firstCopiedAt, firstCopiedAt)
        XCTAssertEqual(item.numberOfCopies, numberOfCopies)
        XCTAssertEqual(item.sourceAppBundleID, sourceAppBundleID)
        XCTAssertEqual(item.sourceAppName, sourceAppName)
        XCTAssertEqual(item.plainText, "after")
        XCTAssertEqual(item.title, "after")
        XCTAssertNotEqual(item.contentHash, "original-hash")
        XCTAssertEqual(storage.fetchAll().count, 1)
    }

    func testCopyLeavesOriginalIntact() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)

        let copy = try service.save(text: "after", for: item, mode: .copy)

        XCTAssertEqual(item.plainText, "before")
        XCTAssertEqual(copy.plainText, "after")
        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.sourceAppName, "Source", "the copy keeps the original's provenance")
        XCTAssertEqual(storage.fetchAll().count, 2)
    }

    func testTextSaveWritesBothPlainTextTypes() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)

        try service.save(text: "after", for: item, mode: .overwrite)

        let types = Set(item.contents.map(\.type))
        XCTAssertEqual(types, [UTType.utf8PlainText.identifier, UTType.plainText.identifier])
    }

    func testTextSaveDropsStaleRichTextRepresentations() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        item.contents.append(
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("stale rtf".utf8))
        )
        try storage.context.save()

        try service.save(text: "after", for: item, mode: .overwrite)

        XCTAssertFalse(item.contents.contains { $0.type == UTType.rtf.identifier })
    }

    func testTextSaveOverCapThrowsTooLarge() {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        let oversized = String(repeating: "a", count: Constants.maxContentSize + 1)

        XCTAssertThrowsError(try service.save(text: oversized, for: item, mode: .overwrite)) { error in
            guard case ItemEditService.EditError.tooLarge = error else {
                return XCTFail("Expected EditError.tooLarge, got \(error)")
            }
        }
    }

    func testImageSaveWritesPNG() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("placeholder", in: storage)

        try service.save(image: makeImage(width: 8, height: 4), for: item, mode: .overwrite)

        let png = item.contents.first { $0.type == UTType.png.identifier }
        XCTAssertNotNil(png?.value)
        XCTAssertEqual(item.title, "Image")
        XCTAssertEqual(NSImage(data: png!.value!)?.pixelSize, CGSize(width: 8, height: 4))
    }

    func testImageSaveDropsTIFFWhenOverCapButKeepsPNG() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("placeholder", in: storage)
        // Flat colour, ~10.4 MB uncompressed (width * height * 4 bytes) — over the
        // cap as TIFF, but PNG compresses a solid fill to a few KB, well under it.
        let image = makeLargeSolidImage(width: 2000, height: 1300)

        try service.save(image: image, for: item, mode: .overwrite)

        let png = item.contents.first { $0.type == UTType.png.identifier }
        XCTAssertNotNil(png?.value)
        XCTAssertLessThanOrEqual(png?.value?.count ?? Int.max, Constants.maxContentSize)
        XCTAssertFalse(item.contents.contains { $0.type == UTType.tiff.identifier })
    }

    func testIsEditableRejectsFileItems() throws {
        let storage = makeStorage()
        let item = ClipboardItem(title: "file", contentHash: "h")
        item.contents = [
            ClipboardItemContent(
                type: UTType.fileURL.identifier,
                value: Data("file:///tmp/a.txt".utf8)
            )
        ]
        storage.context.insert(item)

        XCTAssertFalse(item.isEditable)
    }

    func testIsEditableAcceptsTextItems() throws {
        let storage = makeStorage()
        let item = makeTextItem("hello", in: storage)
        XCTAssertTrue(item.isEditable)
    }

    /// Pins the guard ordering in `ClipboardItem.isEditable`: the file check must run
    /// *before* the image check, not after. This item mimics copying an image file in
    /// Finder, which can carry both a file-URL representation and an image
    /// representation — `primaryType` resolves to `.fileURL` here only because
    /// `ContentType.displayPriority` currently ranks file URLs above images, which is
    /// documented as a display-only preference, not an editability rule. Checking the
    /// file guard first, independent of `primaryType`/`displayPriority` ordering, is
    /// what `isEditable`'s doc comment claims; this test would have passed for the
    /// wrong reason (via the `primaryType == .image` short-circuit never even running)
    /// if it only asserted the outcome without the guard order being what makes that
    /// outcome true regardless of how `displayPriority` is ever tuned.
    func testIsEditableRejectsFileItemsEvenWhenTheyAlsoCarryAnImage() throws {
        let storage = makeStorage()
        let item = ClipboardItem(title: "image file", contentHash: "h")
        item.contents = [
            ClipboardItemContent(
                type: UTType.fileURL.identifier,
                value: Data("file:///tmp/photo.png".utf8)
            ),
            ClipboardItemContent(type: UTType.png.identifier, value: makeImage(width: 2, height: 2).pngData()),
        ]
        storage.context.insert(item)

        XCTAssertEqual(item.primaryType, .fileURL, "fileURL currently outranks image in displayPriority")
        XCTAssertFalse(item.isEditable)
    }
}
