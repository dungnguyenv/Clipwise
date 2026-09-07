import AppKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

@MainActor
final class EditorSessionTests: XCTestCase {

    private func makeService() -> (ItemEditService, StorageManager) {
        let storage = StorageManager(inMemory: true)
        return (ItemEditService(storageManager: storage), storage)
    }

    private func makeTextItem(_ text: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: text, contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    /// A rich-text item as it actually arrives from a real copy — e.g. a browser or
    /// Pages/Word/Notes selection — carrying both a rich representation and a plain-text
    /// fallback. Takes a raw UTI string rather than `UTType` so this also covers formats
    /// with no `UTType` static member, like `com.apple.rtfd`.
    private func makeRichTextItem(_ text: String, richTypeIdentifier: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: text, contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: richTypeIdentifier, value: Data("<rich>".utf8)),
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8)),
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

    private func makeImageItem(_ image: NSImage, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: "Image", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.png.identifier, value: image.pngData())
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    func testInitReturnsNilForNonEditableItem() {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "file", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.fileURL.identifier, value: Data("file:///tmp/a".utf8))
        ]
        storage.context.insert(item)

        XCTAssertFalse(item.isEditable, "a file's text form is just its path, not editable content")
        XCTAssertNil(EditorSession(item: item, editService: service))
    }

    func testFileItemWithPlainTextRepresentationStaysNonEditable() throws {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "file", contentHash: "hash")
        // A file item that *also* carries a plain-text representation of its own path —
        // the case `isEditable`'s file exclusion exists for. A `plainText != nil` check
        // alone would wrongly admit this.
        item.contents = [
            ClipboardItemContent(type: UTType.fileURL.identifier, value: Data("file:///tmp/a.txt".utf8)),
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data("/tmp/a.txt".utf8)),
        ]
        storage.context.insert(item)
        try? storage.context.save()

        XCTAssertFalse(item.isEditable, "a file's plain-text path string is not editable content")
        XCTAssertNil(EditorSession(item: item, editService: service))
    }

    func testInitReturnsNilForRTFOnlyItemWithNoPlainTextFallback() throws {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "rtf", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("<rtf>".utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()

        XCTAssertFalse(item.isEditable, "nothing for the editor to load without a plain-text fallback")
        XCTAssertNil(EditorSession(item: item, editService: service))
    }

    func testRTFItemWithPlainTextIsEditableAndOpensInTextMode() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("hello", richTypeIdentifier: UTType.rtf.identifier, in: storage)

        XCTAssertTrue(item.isEditable)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
    }

    func testHTMLItemWithPlainTextIsEditableAndOpensInTextMode() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("hello", richTypeIdentifier: UTType.html.identifier, in: storage)

        XCTAssertTrue(item.isEditable)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
    }

    func testSavingRichTextItemDropsTheRichRepresentation() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("before", richTypeIdentifier: UTType.rtf.identifier, in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.overwrite))

        XCTAssertEqual(item.plainText, "after")
        XCTAssertFalse(item.contents.contains { $0.type == UTType.rtf.identifier })
        let types = Set(item.contents.map(\.type))
        XCTAssertEqual(types, [UTType.utf8PlainText.identifier, UTType.plainText.identifier])
    }

    func testRTFDRepresentationTriggersTheBannerEvenThoughItDoesNotClassify() throws {
        let (service, storage) = makeService()
        // "com.apple.rtfd" (and "com.apple.flat-rtfd", "com.apple.webarchive") conform to
        // neither `.rtf` nor `.html`, so `ContentType.classify` returns nil for them and
        // `primaryType` falls through to `.text` — this is the TextEdit/Notes-inline-
        // attachment case the banner must still catch.
        let item = makeRichTextItem("hello", richTypeIdentifier: "com.apple.rtfd", in: storage)
        XCTAssertEqual(item.primaryType, .text, "rtfd doesn't classify, so plain text is still primary")

        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertTrue(session.hasRichTextRepresentation)
    }

    func testLegacyPlainTextAliasDoesNotTriggerTheBanner() throws {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "hello", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data("hello".utf8)),
            ClipboardItemContent(type: "com.apple.traditional-mac-plain-text", value: Data("hello".utf8)),
        ]
        storage.context.insert(item)
        try? storage.context.save()

        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertFalse(session.hasRichTextRepresentation)
    }

    func testTextSessionStartsCleanAndTracksEdits() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("hello", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
        XCTAssertFalse(session.hasUnsavedChanges)

        session.text = "hello world"
        XCTAssertTrue(session.hasUnsavedChanges)

        session.text = "hello"
        XCTAssertFalse(session.hasUnsavedChanges, "reverting the text clears the dirty flag")
    }

    func testDetectsRichTextRepresentation() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("hello", in: storage)
        let plain = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertFalse(plain.hasRichTextRepresentation)

        item.contents.append(
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("rtf".utf8))
        )
        let rich = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertTrue(rich.hasRichTextRepresentation)
    }

    func testSaveOverwriteWritesThroughToTheItem() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("before", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.overwrite))

        XCTAssertEqual(item.plainText, "after")
        XCTAssertNil(session.errorMessage)
    }

    func testSaveAsCopyLeavesOriginal() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("before", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.copy))

        XCTAssertEqual(item.plainText, "before")
        XCTAssertEqual(storage.fetchAll().count, 2)
    }

    func testImageSessionOpensInImageModeWithDocument() throws {
        let (service, storage) = makeService()
        let item = makeImageItem(makeImage(width: 8, height: 4), in: storage)

        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        XCTAssertEqual(session.mode, .image)
        let document = try XCTUnwrap(session.document)
        XCTAssertEqual(document.pixelSize, CGSize(width: 8, height: 4))
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    func testImageSaveOverwriteWritesThroughToTheItem() throws {
        let (service, storage) = makeService()
        let item = makeImageItem(makeImage(width: 8, height: 4), in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        XCTAssertTrue(session.save(.overwrite))

        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(item.image?.pixelSize, CGSize(width: 8, height: 4))
    }

    func testImageSaveFailsWhenFlattenedImageIsNil() throws {
        let (service, storage) = makeService()
        let item = makeImageItem(makeImage(width: 8, height: 4), in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        let document = try XCTUnwrap(session.document)

        // Force the document's base image into the one state `flattened()` refuses to
        // render: a zero pixel size (`AnnotationRenderer.flatten` guards on
        // `pixelSize.width/height >= 1`). `applyTransform` is the only way to replace
        // `baseImage` through the document's public API.
        document.applyTransform { _ in NSImage(size: .zero) }
        XCTAssertEqual(document.pixelSize, .zero)

        XCTAssertFalse(session.save(.overwrite))
        XCTAssertEqual(session.errorMessage, "Could not render the edited image.")
    }
}
