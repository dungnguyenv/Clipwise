import Foundation
import SwiftData

@MainActor
final class StorageManager {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() {
        let schema = Schema([ClipboardItem.self, ClipboardItemContent.self])
        let config = ModelConfiguration(
            "Clipwise",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            NSLog("[Clipwise] ModelContainer failed: \(error). Deleting old store and retrying...")
            Self.deleteExistingStore(name: "Clipwise")
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("[Clipwise] Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    private static func deleteExistingStore(name: String) {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            NSLog("[Clipwise] Could not find Application Support directory")
            return
        }

        let possibleDirs = [
            appSupport.appending(path: "default"),
            appSupport,
        ]
        let fm = FileManager.default
        for dir in possibleDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.lastPathComponent.contains(name) ||
                file.lastPathComponent.hasSuffix(".store-shm") ||
                file.lastPathComponent.hasSuffix(".store-wal") {
                do {
                    try fm.removeItem(at: file)
                    NSLog("[Clipwise] Deleted: \(file.path)")
                } catch {
                    NSLog("[Clipwise] Failed to delete \(file.path): \(error)")
                }
            }
        }
    }

    // MARK: - CRUD

    func save(_ item: ClipboardItem) {
        context.insert(item)
        do {
            try context.save()
        } catch {
            NSLog("[Clipwise] Failed to save item: \(error)")
        }
    }

    func delete(_ item: ClipboardItem) {
        context.delete(item)
        do {
            try context.save()
        } catch {
            NSLog("[Clipwise] Failed to delete item: \(error)")
        }
    }

    func deleteAll() {
        do {
            let items = try context.fetch(FetchDescriptor<ClipboardItem>())
            for item in items {
                context.delete(item)
            }
            try context.save()
            NSLog("[Clipwise] Cleared all clipboard history (\(items.count) items)")
        } catch {
            NSLog("[Clipwise] Failed to delete all: \(error)")
        }
    }

    func fetchAll(limit: Int = 200) -> [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            NSLog("[Clipwise] Failed to fetch items: \(error)")
            return []
        }
    }

    func findByHash(_ hash: String) -> ClipboardItem? {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - History Limit

    func enforceHistoryLimit(_ limit: Int) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .forward)]
        )
        guard let all = try? context.fetch(descriptor) else { return }
        let excess = all.count - limit
        if excess > 0 {
            for item in all.prefix(excess) {
                context.delete(item)
            }
            do {
                try context.save()
            } catch {
                NSLog("[Clipwise] Failed to enforce history limit: \(error)")
            }
        }
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        do {
            try context.save()
        } catch {
            NSLog("[Clipwise] Failed to toggle pin: \(error)")
        }
    }
}
