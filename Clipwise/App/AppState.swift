import AppKit
import Foundation

@MainActor
@Observable
final class AppState {
    var items: [ClipboardItem] = []
    var searchQuery: String = ""
    var filteredItems: [ClipboardItem] = []
    var selectedIndex: Int = 0
    var isPanelVisible: Bool = false
    var hoveredItemID: UUID?

    /// Item to preview: hovered item takes priority, otherwise selected item
    var previewItem: ClipboardItem? {
        if let hoveredID = hoveredItemID {
            return filteredItems.first { $0.id == hoveredID }
        }
        guard !filteredItems.isEmpty, selectedIndex < filteredItems.count else { return nil }
        return filteredItems[selectedIndex]
    }

    /// The app that was active before the panel was shown (paste target)
    var previousApp: NSRunningApplication?

    let storageManager: StorageManager
    let clipboardMonitor: ClipboardMonitor
    let appFilterService: AppFilterService
    let pasteService: PasteService
    let searchEngine: SearchEngine
    let itemEditService: ItemEditService

    init() {
        let storage = StorageManager()
        let filter = AppFilterService()

        self.storageManager = storage
        self.appFilterService = filter
        self.clipboardMonitor = ClipboardMonitor(storageManager: storage, appFilterService: filter)
        self.pasteService = PasteService()
        self.searchEngine = SearchEngine()
        self.itemEditService = ItemEditService(storageManager: storage)

        // Register defaults
        UserDefaults.standard.register(defaults: [
            Constants.historyLimitKey: Constants.defaultHistoryLimit,
            Constants.searchModeKey: SearchMode.mixed.rawValue,
            Constants.showDockIconKey: true,
            Constants.hidePasswordsKey: true,
        ])

        loadItems()

        clipboardMonitor.onNewItem = { [weak self] _ in
            self?.loadItems()
        }
    }

    func loadItems() {
        let limit = UserDefaults.standard.integer(forKey: Constants.historyLimitKey)
        items = storageManager.fetchAll(limit: limit > 0 ? limit : Constants.defaultHistoryLimit)
        applySearch()
    }

    func applySearch() {
        let modeString = UserDefaults.standard.string(forKey: Constants.searchModeKey) ?? SearchMode.mixed.rawValue
        let mode = SearchMode(rawValue: modeString) ?? .mixed

        if searchQuery.isEmpty {
            // Show pinned items first, then by date
            filteredItems = items.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.lastCopiedAt > rhs.lastCopiedAt
            }
        } else {
            let results = searchEngine.search(query: searchQuery, in: items, mode: mode)
            filteredItems = results.map(\.item)
        }

        // Reset selection
        selectedIndex = 0
    }

    var onDismissPanel: (() -> Void)?
    var onOpenEditor: ((ClipboardItem) -> Void)?

    func editItem(at index: Int) {
        guard index >= 0, index < filteredItems.count else { return }
        let item = filteredItems[index]
        guard item.isEditable else { return }
        onOpenEditor?(item)
    }

    func selectAndPaste() {
        guard !filteredItems.isEmpty, selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]

        // Update item: move to top of list and reset time
        item.lastCopiedAt = Date()
        item.numberOfCopies += 1
        try? storageManager.context.save()

        pasteService.paste(item, to: previousApp, dismissPanel: onDismissPanel)
    }

    func deleteItem(at index: Int) {
        guard index < filteredItems.count else { return }
        let item = filteredItems[index]
        storageManager.delete(item)
        loadItems()
    }

    func togglePin(at index: Int) {
        guard index < filteredItems.count else { return }
        let item = filteredItems[index]
        storageManager.togglePin(item)
        applySearch()
    }

    func clearAll() {
        storageManager.deleteAll()
        loadItems()
    }

    func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0, newIndex < filteredItems.count {
            selectedIndex = newIndex
        }
    }
}
