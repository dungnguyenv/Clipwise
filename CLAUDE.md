# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Regenerate Xcode project (required after adding/removing files or changing project.yml)
xcodegen generate

# Build (Debug)
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build

# Build (Release)
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Release build

# Run the built app (do NOT use Xcode Run if testing Accessibility features — 
# Xcode rebuilds invalidate macOS Accessibility permission)
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app

# Create DMG for distribution
hdiutil create -volname "Clipwise" -srcfolder <release-app-folder> -ov -format UDZO Clipwise.dmg
```

No SPM dependencies — the project uses only Apple system frameworks.

No test targets exist yet.

## SwiftData Gotchas

- Changing `@Model` fields (adding/removing `@Attribute(.externalStorage)`, renaming properties) causes `SwiftDataError.loadIssueModelContainer`. `StorageManager` auto-recovers by deleting the old store, but users lose history.
- Use `context.delete(item)` in a loop (not `context.delete(model:)`) to ensure cascade delete of `ClipboardItemContent` works correctly.
- Do NOT use `@Attribute(.externalStorage)` on `ClipboardItemContent.value` — causes lazy load issues where `value` returns `nil` when reading back.

## Architecture

Clipwise is a **macOS clipboard manager** (similar to Maccy). It uses a **hybrid SwiftUI + AppKit** architecture:

- **SwiftUI** — all view rendering (inside `NSHostingView`)
- **AppKit** — `NSPanel` (floating popup window), `NSStatusItem` (menu bar icon), `NSApplicationDelegateAdaptor`
- **Carbon HIToolbox** — global hotkeys (`RegisterEventHotKey`)
- **SwiftData** — clipboard history persistence

### App Lifecycle

`ClipwiseApp` (`@main`) → `AppDelegate` (via `@NSApplicationDelegateAdaptor`) → owns everything:
- `NSStatusItem` (menu bar icon)
- `FloatingPanel` (NSPanel subclass — the popup window)
- `AppState` (@Observable — central state shared with all SwiftUI views)
- `HotKeyManager` (global hotkeys: Cmd+Shift+C, Cmd+Shift+V)
- `ClipboardMonitor` (polls `NSPasteboard.changeCount` every 0.5s)

`Info.plist` sets `LSUIElement: true` (agent app). Dock icon visibility is toggled at runtime via `NSApp.setActivationPolicy()`.

### Paste Flow (most complex path)

`selectAndPaste()` → `PasteService.paste()`:
1. Write item contents to `NSPasteboard.general` (with internal marker to avoid re-capture)
2. Dismiss panel
3. `NSApp.yieldActivation` + `targetApp.activate()` to return focus to previous app
4. `Task.detached` polls until target app is actually frontmost (up to 2s)
5. Simulate Cmd+V via `osascript` (primary) or `CGEvent` (fallback — requires Accessibility permission)

### Key Constraints

- **Accessibility permission**: Required for paste simulation. macOS ties this to the binary's code signature — rebuilding in Xcode invalidates it. When developing paste features, build once then run via `open .app` instead of Xcode Run.
- **App Sandbox disabled**: Required for clipboard monitoring, CGEvent posting, and global hotkeys. Documented in `Clipwise.entitlements`.
- **@MainActor everywhere**: All services and state are `@MainActor`-isolated because `NSPasteboard`, `NSStatusItem`, SwiftData `ModelContext`, and AppKit APIs require main thread access.
- **No push API for clipboard**: macOS has no notification for pasteboard changes. Polling `NSPasteboard.changeCount` is the only reliable method.

### Data Model

`ClipboardItem` (SwiftData `@Model`) → has many `ClipboardItemContent` (cascade delete).
Each content stores a UTType identifier string + raw `Data`. One clipboard copy can have multiple representations (e.g., rich text + plain text + HTML).
Duplicates detected via SHA256 hash of all pasteboard data — updates `lastCopiedAt` instead of creating new entry.

### Preview Popover

Each clipboard row has a `.popover(arrowEdge: .trailing)` that shows when the item is hovered or selected. Only one popover is visible at a time — controlled by `AppState.previewItem` (computed: hover takes priority over selection). The popover is attached per-row so it follows the item's vertical position. Max height capped at 1/3 screen height.

### Password Detection

`ClipboardItem.looksLikePassword` uses heuristics: single-line, no spaces, 8-128 chars, 3+ character classes (upper/lower/digit/symbol), or known API key prefixes (`sk-`, `ghp_`, `eyJ`, etc.). Sensitive items show `••••••••` in the UI but can still be pasted.
Password detection excludes URLs, emails, file paths, and domains to avoid false positives. Controlled by `hidePasswords` UserDefaults toggle.
