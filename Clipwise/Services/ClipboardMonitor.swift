import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    /// Marker type to identify internal paste operations (so we don't re-capture them)
    static let internalMarker = NSPasteboard.PasteboardType("com.clipwise.internal")

    /// Concealed type used by password managers (nspasteboard.org convention)
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Max data size per content type (10MB)
    private static let maxContentSize = 10_000_000

    private let storageManager: StorageManager
    private let appFilterService: AppFilterService
    var onNewItem: ((ClipboardItem) -> Void)?

    init(storageManager: StorageManager, appFilterService: AppFilterService) {
        self.storageManager = storageManager
        self.appFilterService = appFilterService
    }

    // Note: stop() must be called before this object is released.
    // deinit cannot access @MainActor-isolated `timer` directly.

    func start(interval: TimeInterval = 0.5) {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Skip our own paste operations
        if pasteboard.types?.contains(Self.internalMarker) == true {
            return
        }

        // Check if source app is ignored
        if let app = NSWorkspace.shared.frontmostApplication,
           appFilterService.isIgnored(app) {
            return
        }

        // Check for concealed type (password managers)
        if pasteboard.types?.contains(Self.concealedType) == true {
            return
        }

        processPasteboardItems()
    }

    private func processPasteboardItems() {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return }

        let hash = ClipboardItem.generateHash(from: items)

        // Check for duplicate
        if let existing = storageManager.findByHash(hash) {
            existing.lastCopiedAt = Date()
            existing.numberOfCopies += 1
            do {
                try storageManager.context.save()
            } catch {
                NSLog("[Clipwise] Failed to update duplicate item: \(error)")
            }
            onNewItem?(existing)
            return
        }

        let title = ClipboardItem.generateTitle(from: items)
        let sourceApp = NSWorkspace.shared.frontmostApplication

        let clipboardItem = ClipboardItem(
            title: title,
            sourceAppBundleID: sourceApp?.bundleIdentifier,
            sourceAppName: sourceApp?.localizedName,
            contentHash: hash
        )

        // Extract all content representations
        for pbItem in items {
            for type in pbItem.types {
                guard let data = pbItem.data(forType: type) else { continue }
                guard data.count < Self.maxContentSize else { continue }

                let content = ClipboardItemContent(
                    type: type.rawValue,
                    value: data
                )
                clipboardItem.contents.append(content)
            }
        }

        storageManager.save(clipboardItem)

        let limit = UserDefaults.standard.integer(forKey: Constants.historyLimitKey)
        if limit > 0 {
            storageManager.enforceHistoryLimit(limit)
        }

        onNewItem?(clipboardItem)
    }
}
