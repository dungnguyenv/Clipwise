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
    /// fallback. `richType` is expected to be `.rtf` or `.html`.
    private func makeRichTextItem(_ text: String, richType: UTType, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: text, contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: richType.identifier, value: Data("<rich>".utf8)),
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8)),
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

    func testRTFItemWithPlainTextIsEditableAndOpensInTextMode() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("hello", richType: .rtf, in: storage)

        XCTAssertTrue(item.isEditable)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
    }

    func testHTMLItemWithPlainTextIsEditableAndOpensInTextMode() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("hello", richType: .html, in: storage)

        XCTAssertTrue(item.isEditable)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
    }

    func testSavingRichTextItemDropsTheRichRepresentation() throws {
        let (service, storage) = makeService()
        let item = makeRichTextItem("before", richType: .rtf, in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.overwrite))

        XCTAssertEqual(item.plainText, "after")
        XCTAssertFalse(item.contents.contains { $0.type == UTType.rtf.identifier })
        let types = Set(item.contents.map(\.type))
        XCTAssertEqual(types, [UTType.utf8PlainText.identifier, UTType.plainText.identifier])
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
}
