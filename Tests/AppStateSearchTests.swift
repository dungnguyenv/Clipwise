import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

/// Search must not become a side channel around the password mask. The list shows a
/// concealed item as `••••••••`, but `SearchEngine` matches against the real title —
/// so with the mask on, typing a query one character at a time would confirm the
/// secret's prefix by whether the masked row stays in the results. Concealed items
/// therefore drop out of search entirely while "Hide passwords & secrets" is on.
@MainActor
final class AppStateSearchTests: XCTestCase {

    private func makeItem(_ text: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: text, contentHash: "hash-\(text)")
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8))
        ]
        storage.context.insert(item)
        return item
    }

    func testSearchableItemsDropConcealedItemsWhileHidingPasswords() {
        let storage = StorageManager(inMemory: true)
        let prose = makeItem("meeting notes for monday", in: storage)
        let secret = makeItem("Xk9#mP2$vLq7", in: storage)

        let searchable = AppState.searchableItems([prose, secret], hidePasswords: true)

        XCTAssertEqual(searchable.map(\.id), [prose.id])
    }

    func testSearchableItemsKeepEverythingWhenNotHidingPasswords() {
        let storage = StorageManager(inMemory: true)
        let prose = makeItem("meeting notes for monday", in: storage)
        let secret = makeItem("Xk9#mP2$vLq7", in: storage)

        let searchable = AppState.searchableItems([prose, secret], hidePasswords: false)

        XCTAssertEqual(searchable.map(\.id), [prose.id, secret.id])
    }
}
