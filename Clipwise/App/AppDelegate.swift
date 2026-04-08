import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var floatingPanel: FloatingPanel!
    private var settingsWindow: NSWindow?
    var appState: AppState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        appState.onDismissPanel = { [weak self] in
            self?.hidePanel()
        }

        setupStatusItem()
        setupFloatingPanel()
        setupHotKey()
        startClipboardMonitor()
        configureDockIcon()
        checkAccessibility()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipwise")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    // MARK: - Floating Panel

    private func setupFloatingPanel() {
        let contentView = PanelContentView(
            appState: appState,
            onDismiss: { [weak self] in
                self?.hidePanel()
            },
            onOpenSettings: { [weak self] in
                self?.hidePanel()
                // Delay to let panel fully dismiss before showing settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.openSettings()
                }
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        floatingPanel = FloatingPanel(contentView: hostingView)

        floatingPanel.onDismiss = { [weak self] in
            self?.appState.isPanelVisible = false
            self?.appState.searchQuery = ""
        }
    }

    func togglePanel() {
        if floatingPanel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        // Capture the currently active app before showing panel
        appState.previousApp = NSWorkspace.shared.frontmostApplication

        appState.loadItems()
        appState.searchQuery = ""
        appState.selectedIndex = 0
        appState.isPanelVisible = true

        floatingPanel.showNearStatusItem(statusItem)

        // Activate our app to receive keyboard events
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        floatingPanel.dismiss()
        appState.isPanelVisible = false
        appState.searchQuery = ""
    }

    // MARK: - Hot Key

    private func setupHotKey() {
        // Cmd+Shift+C → toggle panel near menu bar
        HotKeyManager.shared.register(
            id: 1,
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.togglePanel()
        }

        // Cmd+Shift+V → show panel near cursor
        HotKeyManager.shared.register(
            id: 2,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.showPanelAtCursor()
        }
    }

    func showPanelAtCursor() {
        if floatingPanel.isVisible {
            hidePanel()
            return
        }

        appState.previousApp = NSWorkspace.shared.frontmostApplication
        appState.loadItems()
        appState.searchQuery = ""
        appState.selectedIndex = 0
        appState.isPanelVisible = true

        floatingPanel.showNearCursor()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Clipboard Monitor

    private func startClipboardMonitor() {
        appState.clipboardMonitor.start(interval: Constants.pollingInterval)
    }

    // MARK: - Dock Icon

    private func configureDockIcon() {
        let showDock = UserDefaults.standard.bool(forKey: Constants.showDockIconKey)
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    // MARK: - Settings Window

    func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "General"
        window.titleVisibility = .visible
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    // MARK: - Accessibility

    private func checkAccessibility() {
        if !AccessibilityHelper.isAccessibilityEnabled {
            AccessibilityHelper.requestAccessibility()
        }
    }
}
