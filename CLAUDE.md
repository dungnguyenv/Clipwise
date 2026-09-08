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

Unit tests live in the `ClipwiseTests` target (`Tests/`, declared in `project.yml`).
Run them with `make test`, which regenerates the project first.

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

### Item Editor

An item is editable when its primary type is `.image`, or it has a plain-text
representation and is not a file item (`ClipboardItem.isEditable`). This is
deliberately **not** `primaryType == .text` — `ContentType.displayPriority`
ranks rtf and html above text, so anything copied from a browser, Pages, or
Word reports a primary type of `.html` or `.rtf` and would never have shown a
pencil under that check. `EditorSession` opens such items in `.text` mode,
converting to plain text on save; the rich-text warning banner (below) is what
flags that conversion before it happens.

Entry points: a pencil button that appears on row hover/selection, a
context-menu `Edit` entry, and `Cmd+E` on the selected row. The first two go
through `AppState.editItem(at:)` → `AppState.onOpenEditor` →
`EditorWindowController`. `Cmd+E` is handled in
`FloatingPanel.performKeyEquivalent(_:)`, not in `SearchFieldView`'s text
field — the app installs no custom `NSMenu`, so ⌘E is claimed by the default
Edit menu's "Use Selection for Find" and dispatched through the key-equivalent
path before an ordinary field key handler would see it. Overriding
`performKeyEquivalent` on the panel wins regardless of whether AppKit checks
the key window or the menu first.

The editor opens in its own resizable `NSWindow`, not in the panel —
`FloatingPanel` dismisses itself on `resignKey`, so `AppDelegate` hides the panel
and opens the window 0.15s later, the same sequence used for Settings.

`EditorSession` is the shared state between the views and the window; the window
reads `hasUnsavedChanges` in `windowShouldClose` to decide whether to prompt.
`EditorWindowController` has two distinct close paths and they must stay
distinct: the post-save path (`onFinished`) nils the window's delegate before
calling `close()`, skipping `windowShouldClose` entirely, because
`EditorSession` never refreshes its "original" snapshot after a save and would
otherwise report unsaved changes immediately after a successful one; the
cancel/Esc path (`onCancel`) calls `performClose(_:)`, which does consult
`windowShouldClose`.

Quitting is a third path and reaches neither of those. AppKit only asks
`windowShouldClose` when a *window* is closed, and does not walk the windows on
termination unless the app is document-based — Clipwise isn't. So
`AppDelegate.applicationShouldTerminate` calls
`EditorWindowController.confirmTerminate()`, which runs the same prompt for each
dirty editor and returns `.terminateCancel` if any is cancelled. This covers ⌘Q
and the Settings "Quit" button, which calls `NSApp.terminate(nil)` directly. All
three paths share one `confirmDiscarding(_:)` — add a fourth way to close an
editor and it must go through that too, or edits vanish silently.

**Image editing is vector-based.** `ImageEditorDocument` holds the base `NSImage`
plus an array of `ImageAnnotation` values in **image-pixel space with a top-left
origin** — never view coordinates, which is what keeps annotations locked to the
image when the window resizes. `AnnotationRenderer.draw` is called by both the
live `Canvas` and the `ImageRenderer`-based `flatten`, so preview and saved
output cannot diverge. Undo/redo is snapshot push/pop, capped at 30.

Geometric transforms (crop/rotate/flip/resize) flatten annotations into the base
image first — so after a crop you can no longer undo individual strokes, only the
whole transform step.

**Saving text discards RTF/HTML representations.** `PasteService` replays every
stored representation, so keeping a stale RTF blob would paste the pre-edit
content into Pages or Word. The editor shows a warning banner when this
applies. The banner's trigger is an explicit set of rich-text types matched by
**conformance** — rtf, rtfd, flatRTFD, html, webArchive — not a check against
`.rtf`/`.html` conformance alone: RTFD and web-archive content conforms to
neither, so that narrower check silently missed TextEdit and Notes copies that
carry attachments. Inverting the test instead (warn on anything that fails to
conform to `.plainText`) was also tried and rejected — it fired on every plain
URL/vCard copy. Keep the explicit set; don't "simplify" it back to either
alternative.

Two SDK quirks worth knowing before touching the renderer or its tests:
- `NSBitmapImageRep.setColor` zeroes pixels when handed `NSColor.white` or
  `.black` on this SDK. Every test fixture in this project builds colours with
  `NSColor(deviceRed:green:blue:alpha:)` for that reason.
- The highlighter's `blendMode = .multiply` must be set on the *outer* graphics
  context, not inside a `drawLayer` callback. A layer starts with a fresh,
  transparent backdrop, so setting the blend mode inside it multiplies against
  nothing — a no-op that silently reduced the highlighter to a plain
  35%-alpha stroke and went unnoticed through five review passes.

### Password Detection

`ClipboardItem.looksLikePassword(_:)` (static and pure, pinned by `PasswordDetectionTests`) uses heuristics: single-line, no spaces, 8-128 chars, 3+ character classes (upper/lower/digit/symbol), known API key prefixes (`sk-`, `ghp_`, `glpat-`, `eyJ`, etc.), or a PEM `-----BEGIN … PRIVATE KEY` block — the one multi-line case, checked before the shape guard. The instance property feeds it the item's plain text. Sensitive items show `••••••••` in the list and "Sensitive content hidden" in the preview popover (the popover also drops its char count, which would leak the length), but can still be pasted.
Password detection excludes URLs, emails, file paths, and domains to avoid false positives. Controlled by the `hidePasswords` UserDefaults toggle.

While the toggle is on, concealed items are also **excluded from search results** (`AppState.searchableItems`): `SearchEngine` matches the real title, so a masked row that survives each keystroke would confirm the secret one character at a time. The item editor is deliberately *not* gated — per the item-editor spec, a sensitive item opens in the editor showing its real text.
