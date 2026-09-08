import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

/// Characterisation tests for `StorageManager.enforceHistoryLimit`.
///
/// This runs on every single clipboard capture, so it is the one storage call
/// whose cost is worth pinning down: the limit applies to *unpinned* items only,
/// pinned items are neither counted nor deleted, and the survivors are always the
/// newest by `lastCopiedAt`. These tests exist so that rewriting the fetch for
/// speed cannot quietly change any of those three rules.
@MainActor
final class StorageManagerHistoryLimitTests: XCTestCase {

    private func makeStorage() -> StorageManager {
        StorageManager(inMemory: true)
    }

    /// Inserts an item whose `lastCopiedAt` is `ageInSeconds` in the past, so tests
    /// can control recency ordering instead of relying on insertion order.
    @discardableResult
    private func insertItem(
        title: String,
        ageInSeconds: TimeInterval,
        isPinned: Bool = false,
        in storage: StorageManager
    ) -> ClipboardItem {
        let item = ClipboardItem(title: title, contentHash: "hash-\(title)")
        item.lastCopiedAt = Date(timeIntervalSinceNow: -ageInSeconds)
        item.isPinned = isPinned
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(title.utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    private func remainingTitles(in storage: StorageManager) -> [String] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
        )
        return (try? storage.context.fetch(descriptor))?.map(\.title) ?? []
    }

    func testKeepsEverythingWhenUnderLimit() {
        let storage = makeStorage()
        insertItem(title: "a", ageInSeconds: 30, in: storage)
        insertItem(title: "b", ageInSeconds: 20, in: storage)
        insertItem(title: "c", ageInSeconds: 10, in: storage)

        storage.enforceHistoryLimit(10)

        XCTAssertEqual(remainingTitles(in: storage), ["c", "b", "a"])
    }

    func testKeepsEverythingWhenExactlyAtLimit() {
        let storage = makeStorage()
        insertItem(title: "a", ageInSeconds: 30, in: storage)
        insertItem(title: "b", ageInSeconds: 20, in: storage)
        insertItem(title: "c", ageInSeconds: 10, in: storage)

        storage.enforceHistoryLimit(3)

        XCTAssertEqual(remainingTitles(in: storage), ["c", "b", "a"])
    }

    func testDeletesOldestItemsBeyondLimit() {
        let storage = makeStorage()
        insertItem(title: "oldest", ageInSeconds: 50, in: storage)
        insertItem(title: "older", ageInSeconds: 40, in: storage)
        insertItem(title: "middle", ageInSeconds: 30, in: storage)
        insertItem(title: "newer", ageInSeconds: 20, in: storage)
        insertItem(title: "newest", ageInSeconds: 10, in: storage)

        storage.enforceHistoryLimit(2)

        XCTAssertEqual(remainingTitles(in: storage), ["newest", "newer"])
    }

    /// Pinned items are exempt from the limit *and* excluded from the count, so a
    /// history full of pins still keeps `limit` unpinned items alongside them.
    func testPinnedItemsAreNeitherDeletedNorCountedTowardTheLimit() {
        let storage = makeStorage()
        insertItem(title: "pinned-old", ageInSeconds: 60, isPinned: true, in: storage)
        insertItem(title: "pinned-older", ageInSeconds: 50, isPinned: true, in: storage)
        insertItem(title: "oldest", ageInSeconds: 40, in: storage)
        insertItem(title: "middle", ageInSeconds: 30, in: storage)
        insertItem(title: "newest", ageInSeconds: 10, in: storage)

        storage.enforceHistoryLimit(2)

        XCTAssertEqual(
            remainingTitles(in: storage),
            ["newest", "middle", "pinned-older", "pinned-old"]
        )
    }

    /// The capture path calls this after every save, so the steady state — already at
    /// the limit, one new item arrives — is the case that actually runs in production.
    func testTrimsExactlyOneItemInTheSteadyState() {
        let storage = makeStorage()
        for index in 0..<5 {
            insertItem(title: "item-\(index)", ageInSeconds: TimeInterval(50 - index * 10), in: storage)
        }

        storage.enforceHistoryLimit(4)

        XCTAssertEqual(remainingTitles(in: storage), ["item-4", "item-3", "item-2", "item-1"])
    }

    /// Cascade delete must take the trimmed items' contents with them, otherwise the
    /// store grows without bound even though the item count looks correct.
    func testTrimmedItemsTakeTheirContentsWithThem() {
        let storage = makeStorage()
        insertItem(title: "oldest", ageInSeconds: 30, in: storage)
        insertItem(title: "newest", ageInSeconds: 10, in: storage)

        storage.enforceHistoryLimit(1)

        let contents = (try? storage.context.fetch(FetchDescriptor<ClipboardItemContent>())) ?? []
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents.first?.value.flatMap { String(data: $0, encoding: .utf8) }, "newest")
    }
}
