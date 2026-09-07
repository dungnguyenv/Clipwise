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

    func testOverwriteKeepsIdentityAndReplacesContent() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        item.isPinned = true
        let id = item.id
        let firstCopiedAt = item.firstCopiedAt

        try service.save(text: "after", for: item, mode: .overwrite)

        XCTAssertEqual(item.id, id)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.firstCopiedAt, firstCopiedAt)
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
}
