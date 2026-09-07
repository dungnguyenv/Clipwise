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

    func testInitReturnsNilForNonEditableItem() {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "file", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.fileURL.identifier, value: Data("file:///tmp/a".utf8))
        ]
        storage.context.insert(item)

        XCTAssertNil(EditorSession(item: item, editService: service))
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
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertFalse(session.hasRichTextRepresentation)

        // Mutate the same item `session` already holds a reference to, rather than
        // constructing a second `EditorSession` from it: `.rtf` outranks `.text` in
        // `ContentType.displayPriority`, so once this content is appended,
        // `item.primaryType` becomes `.rtf` and `EditorSession.init?` — by design,
        // see its doc comment — would return nil for it. `hasRichTextRepresentation`
        // is a live computed property over `item.contents`, so the already-open
        // session picks up the change without needing to reopen.
        item.contents.append(
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("rtf".utf8))
        )
        XCTAssertTrue(session.hasRichTextRepresentation)
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
