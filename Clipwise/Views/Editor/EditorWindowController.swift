import AppKit
import SwiftUI

/// Owns the editor windows. One window per item, keyed by item id.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {

    private struct Entry {
        let window: NSWindow
        let session: EditorSession
    }

    private var entries: [UUID: Entry] = [:]
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func open(_ item: ClipboardItem) {
        let itemID = item.id

        if let existing = entries[itemID] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let session = EditorSession(item: item, editService: appState.itemEditService) else {
            // `ClipboardItem.isEditable` is a cheap heuristic (primaryType / plainText
            // presence) and can say yes for content `EditorSession.init?` then refuses —
            // e.g. an image whose data fails to decode. Without this alert the user gets
            // a pencil, clicks it, and nothing happens: no window, no explanation.
            presentCannotOpenAlert()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Constants.editorWindowWidth,
                height: Constants.editorWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let rootView = EditorRootView(
            session: session,
            onFinished: { [weak self, weak window] in
                self?.appState.loadItems()
                self?.forceClose(window)
            },
            onCancel: { [weak window] in
                // Goes through the window so windowShouldClose can prompt.
                window?.performClose(nil)
            }
        )

        window.title = session.mode == .image ? "Edit Image" : "Edit Text"
        window.contentView = NSHostingView(rootView: rootView)
        window.contentMinSize = NSSize(
            width: Constants.editorMinWidth,
            height: Constants.editorMinHeight
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        entries[itemID] = Entry(window: window, session: session)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    /// Runs only for the `onCancel` close path (`window.performClose(nil)`, including
    /// Esc) — the `onFinished` path in `open(_:)` calls `forceClose`, which nils
    /// `delegate` before `close()` specifically so this never runs after a successful
    /// save. See `forceClose`'s doc comment for why that split exists.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session = entries.values.first(where: { $0.window === sender })?.session else {
            return true
        }
        guard session.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Save your edits before closing?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Save as Copy")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard session.save(.overwrite) else { return false }
            appState.loadItems()
            return true
        case .alertSecondButtonReturn:
            guard session.save(.copy) else { return false }
            appState.loadItems()
            return true
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        entries = entries.filter { $0.value.window !== window }
    }

    // MARK: - Private

    private func presentCannotOpenAlert() {
        // `runModal()` is app-modal and blocks the run loop until dismissed. Clipwise is
        // LSUIElement and this fires ~0.15s after the panel was hidden, so activation is
        // very likely already in effect — but if it isn't, an unactivated app-modal alert
        // can render off-screen or behind other windows, and the app looks hung with no
        // visible way to dismiss it. Match `open(_:)`'s success path, which activates
        // before showing its window for the same reason.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Can't Open Item"
        alert.informativeText = "This item's content could not be loaded for editing."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Closes without running the unsaved-changes guard — used after a save, where
    /// there is nothing left to confirm. Deliberately distinct from routing through
    /// `window.performClose(nil)` (the `onCancel` path above): `EditorSession` never
    /// refreshes `originalText`/`hasUnsavedChanges` after a save, so a guard reading
    /// that state here would (wrongly) think there's still something unsaved. Setting
    /// `delegate = nil` before `close()` is what skips the guard — Task 10 adds a
    /// `windowShouldClose` implementation to this delegate that reads `hasUnsavedChanges`,
    /// and it must never see this close. Don't collapse this into `onCancel`'s path.
    private func forceClose(_ window: NSWindow?) {
        guard let window else { return }
        entries = entries.filter { $0.value.window !== window }
        window.delegate = nil
        window.close()
    }
}
