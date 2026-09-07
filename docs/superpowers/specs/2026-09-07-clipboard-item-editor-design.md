# Clipboard Item Editor — Design

Date: 2026-09-07
Status: Approved for implementation

## 1. Overview

Add an editor for clipboard history items. Opening an item in the editor lets the
user change its content and write the result back to history, either overwriting
the original item or creating a new one.

Two content kinds are supported in v1:

- **Text** — a plain-text editor.
- **Image** — an annotation editor: freehand drawing, shapes, text overlay,
  redaction, and geometric transforms (crop / rotate / flip / resize).

### Goals

- Editing must never interfere with the existing one-click paste flow, which is
  the app's primary interaction.
- What the user sees on the image canvas is exactly what gets saved (WYSIWYG).
- No `@Model` schema changes — a schema change triggers
  `SwiftDataError.loadIssueModelContainer` and wipes the user's history
  (see CLAUDE.md).

### Non-goals (v1)

- Editing `fileURL`, `rtf`, or `html` items.
- Rich-text editing. Editing a text item produces plain text.
- Selecting / moving / resizing an annotation after it is placed (undo instead).
- Canvas zoom and pan.
- Exporting the edited image to a file on disk.

## 2. Entry points

The editor is reached three ways, all of which leave click-to-paste untouched:

1. **Hover button** — `ClipboardRowView` shows a `pencil.circle` button when
   `isHovering || isSelected`, placed before the pin indicator. It is a SwiftUI
   `Button`, so it consumes the click and the row's `onTapGesture`
   (`ClipboardListView.swift:23`) does not fire.
2. **Context menu** — an `Edit` entry above `Pin`.
3. **Keyboard** — `Cmd+E` edits the currently selected item.
   `SearchFieldView` already routes keys via `.onKeyPress`; add a modifier-aware
   phase handler:

   ```swift
   .onKeyPress(phases: .down) { press in
       guard press.modifiers.contains(.command), press.characters == "e" else { return .ignored }
       onEdit()
       return .handled
   }
   ```

All three are gated on a new computed property:

```swift
// ClipboardItem
var isEditable: Bool { primaryType == .text || primaryType == .image }
```

Sensitive items (`looksLikePassword`) are editable; the editor shows the real
text rather than the `••••••••` mask used in the list.

## 3. Editor window

`EditorWindowController` (AppKit, `@MainActor`) owns the windows.

- `NSWindow`, style `[.titled, .closable, .miniaturizable, .resizable]`,
  default 720×560, min 520×420, content is an `NSHostingView(EditorRootView)`.
- Window title: `Edit Text` / `Edit Image`.
- One window per item, keyed by `ClipboardItem.id`. Re-opening an item that is
  already open focuses the existing window instead of creating a second one.
- `isReleasedWhenClosed = false`; the controller drops its reference in
  `windowWillClose`.

### Opening sequence

`FloatingPanel` sets `hidesOnDeactivate = true` and dismisses itself in
`resignKey`, so a new window would race the panel teardown. Reuse the sequence
already proven by `onOpenSettings` (`AppDelegate.swift:56-62`):

```
hidePanel() → DispatchQueue.main.asyncAfter(0.15) → open editor window → NSApp.activate(ignoringOtherApps: true)
```

Wiring mirrors `AppState.onDismissPanel`: `AppState` gains
`var onOpenEditor: ((ClipboardItem) -> Void)?` and `func editItem(at index: Int)`,
and `AppDelegate` installs the closure at launch.

### Closing with unsaved changes

`windowShouldClose` returns `false` and runs an `NSAlert` sheet with four
buttons: **Save**, **Save as Copy**, **Discard**, **Cancel**. Save paths close
the window on success.

## 4. Text editor — `TextEditorPane`

- A `TextEditor` filling the window, `.font(.system(size: 13, design: .monospaced))`.
- Footer: character count and line count.
- Undo/redo is the native `NSTextView` stack behind `TextEditor` — `Cmd+Z` and
  `Cmd+Shift+Z` work with no extra code. `hasUnsavedChanges` is simply
  `text != originalText`.
- If the original item carries an `rtf` or `html` representation, show an inline
  warning: *"Saving converts this item to plain text."* This is not cosmetic —
  `PasteService.writeToPasteboard` replays every stored representation, so a
  stale RTF blob would paste the **pre-edit** content into Pages or Word.
- On save, the item's contents are replaced with exactly two representations:
  `public.utf8-plain-text` and `public.plain-text`, both UTF-8 encoded.

## 5. Image editor

### 5.1 Tools

| Tool | Behaviour |
| --- | --- |
| Pen | Freehand stroke, current color and width. |
| Highlighter | Same stroke geometry, alpha 0.35, width ×3, drawn with `.multiply` blend. |
| Arrow | Drag from tail to head; head is a filled triangle scaled to line width. |
| Rectangle | Drag to define; stroked outline. |
| Ellipse | Drag to define; stroked outline. |
| Text | Click to place, inline field, commit on Return or click-away. |
| Redact | Drag a rect; renders the pixelated base image clipped to that rect. |
| Crop | Drag a rect, then confirm; destructive (see 5.4). |

Plus, outside the tool picker: Rotate ↺ / ↻ (90°), Flip horizontal / vertical,
Resize (width × height, aspect-lock toggle), color picker, stroke-width slider,
Undo / Redo.

Highlighter and Redact are additions beyond the original request. Highlighter is
the pen path with different shading — near-zero extra cost. Redact is the most
used annotation when sharing a screenshot, and the pixelated-base-image approach
below makes it cheap.

### 5.2 Annotation model — `Models/ImageAnnotation.swift`

```swift
enum EditorTool: String, CaseIterable, Identifiable {
    case pen, highlighter, arrow, rectangle, ellipse, text, redact, crop
}

struct ImageAnnotation: Identifiable, Equatable {
    let id: UUID
    var kind: Kind
    var color: Color        // SwiftUI Color — GraphicsContext shades with it directly
    var lineWidth: CGFloat

    enum Kind: Equatable {
        case stroke(points: [CGPoint], highlight: Bool)
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(String, origin: CGPoint, fontSize: CGFloat)
        case redact(CGRect)
    }
}
```

**Coordinate space: image pixels, top-left origin, y down.** Every point and
rect above is in that space, never in view space. This is what keeps annotations
locked to the image when the window is resized. The canvas converts pointer
locations with a single scale factor derived from the fitted display rect.

Pixel size comes from the largest `NSBitmapImageRep` (`pixelsWide` / `pixelsHigh`),
falling back to `NSImage.size` when there is no bitmap rep — `NSImage.size` is in
points and would silently halve dimensions on a Retina screenshot.

### 5.3 Document and undo — `Models/ImageEditorDocument.swift`

```swift
@MainActor @Observable
final class ImageEditorDocument {
    private(set) var baseImage: NSImage
    private(set) var pixelSize: CGSize
    var annotations: [ImageAnnotation]
    private(set) var hasUnsavedChanges: Bool

    func pushUndoSnapshot()   // call before every mutation
    func undo()
    func redo()
}
```

This type is image-only. The text pane holds a plain `String` and inherits undo
from the `NSTextView` backing SwiftUI's `TextEditor`, so there is no reason to
route text through a snapshot stack.

A snapshot is `{ baseImage, annotations }`. `NSImage` is stored by reference and
only replaced by a transform, so a stack of 30 snapshots costs one array of
value types plus a handful of image references — not 30 bitmaps.

- Undo stack capped at 30; oldest dropped.
- Any new mutation clears the redo stack.
- `Cmd+Z` undo, `Cmd+Shift+Z` redo.

### 5.4 Rendering — `Services/AnnotationRenderer.swift`

One drawing function serves both the live canvas and the export path. This is
the whole reason to prefer the vector model: preview and saved output cannot
drift apart, because there is only one implementation.

```swift
enum AnnotationRenderer {
    static func draw(
        annotations: [ImageAnnotation],
        pixelatedBase: Image?,       // for redact
        in context: inout GraphicsContext,
        imageSize: CGSize
    )

    @MainActor
    static func flatten(_ document: ImageEditorDocument) -> NSImage?
}
```

- `ImageCanvasView` draws the base image fitted to the view, then calls `draw`
  inside a `Canvas` scaled by `displayRect.width / pixelSize.width`.
- `flatten` renders an `AnnotatedImageView` sized `pixelSize` through SwiftUI's
  `ImageRenderer` with `scale = 1`, producing an `NSImage` at native resolution.
- Redact draws a cached, fully pixelated copy of the base image clipped to the
  annotation's rect. The cache is invalidated whenever `baseImage` changes.

**Fallback:** if `ImageRenderer` output proves lossy (text metrics, blend modes),
swap `flatten` for a `CGContext`-backed renderer that calls the *same* `draw`
function through a `GraphicsContext`-equivalent shim. The tool set does not
change; only the export backend does.

### 5.5 Transforms — `Services/ImageTransformService.swift`

```swift
enum ImageTransformService {
    static func crop(_ image: NSImage, to rect: CGRect) -> NSImage?
    static func rotate(_ image: NSImage, degrees: CGFloat) -> NSImage?   // ±90
    static func flip(_ image: NSImage, horizontal: Bool) -> NSImage?
    static func resize(_ image: NSImage, to size: CGSize) -> NSImage?
    static func pixelated(_ image: NSImage, blockSize: CGFloat) -> NSImage?
}
```

Implemented over `CGImage` + `CGContext`, not `NSImage.lockFocus`, so results are
exact at the pixel level and independent of the current screen's backing scale.
`pixelated` uses `CIPixellate` with `blockSize` proportional to the image's
smaller dimension (min 8 px).

**Any transform flattens first.** Applying a transform calls
`flatten(document)`, makes the result the new `baseImage`, and clears
`annotations`. This avoids an entire class of coordinate bugs (what does a
stroke's point mean after a 90° rotation and a crop?) at the cost of making
earlier annotations non-undoable individually — the undo stack still restores
the pre-transform state as a whole.

## 6. Save semantics

Two buttons in the editor's footer, plus keyboard equivalents:

| Action | Key | Result |
| --- | --- | --- |
| Save | `Cmd+S` | Overwrites the original item. Preserves `id`, `firstCopiedAt`, `isPinned`, `numberOfCopies`, `sourceAppBundleID`, `sourceAppName`. Updates `title`, `contentHash`, `lastCopiedAt`, and all contents. |
| Save as Copy | `Cmd+Shift+S` | Inserts a new `ClipboardItem`; the original is untouched. The copy inherits the original's source-app fields so provenance is not lost. |
| Cancel | `Esc` | Closes, with the unsaved-changes guard from §3. |

Both save paths close the window and call `appState.loadItems()` so the panel
reflects the change immediately.

### Representations written

- **Text:** `public.utf8-plain-text`, `public.plain-text`.
- **Image:** `public.png` always; `public.tiff` additionally when its encoded
  size is within the limit (some older apps read only TIFF from the pasteboard).

### Size limit

`ClipboardMonitor.maxContentSize` is 10 MB per representation. The editor honours
it:

- PNG over the limit → `NSAlert` explaining the image is too large for history,
  suggesting the Resize tool. Save is blocked; the window stays open.
- TIFF over the limit → silently skipped, PNG-only item is saved.

## 7. Persistence — `Services/ItemEditService.swift`

```swift
@MainActor
final class ItemEditService {
    enum SaveMode { case overwrite, copy }
    enum EditError: Error { case encodingFailed, tooLarge(bytes: Int) }

    init(storageManager: StorageManager)

    func save(text: String, for item: ClipboardItem, mode: SaveMode) throws
    func save(image: NSImage, for item: ClipboardItem, mode: SaveMode) throws
}
```

Replacing contents follows the cascade-delete rule from CLAUDE.md — delete each
`ClipboardItemContent` individually rather than relying on `delete(model:)`:

```swift
let old = item.contents
item.contents = newContents
for content in old { context.delete(content) }
try context.save()
```

`ClipboardItem` gains a hash overload alongside the existing pasteboard one:

```swift
static func generateHash(from representations: [(type: String, data: Data)]) -> String
```

It hashes each `data` in the order given, matching the SHA256-hex format of the
existing `generateHash(from: [NSPasteboardItem])`.

Title regeneration reuses the existing rule: first non-empty line, capped at 200
characters, for text; the literal `"Image"` for images.

### Accepted trade-off

`contentHash` is not `@Attribute(.unique)` — only `id` is. If an edit happens to
produce content identical to another stored item, two rows share a hash and
`StorageManager.findByHash` may return either. The consequence is limited to
which row a future duplicate copy bumps. Not worth deduplicating in v1.

## 8. File layout

```
Add:
  Clipwise/Models/ImageAnnotation.swift
  Clipwise/Models/ImageEditorDocument.swift
  Clipwise/Services/AnnotationRenderer.swift
  Clipwise/Services/ImageTransformService.swift
  Clipwise/Services/ItemEditService.swift
  Clipwise/Views/Editor/EditorWindowController.swift
  Clipwise/Views/Editor/EditorRootView.swift
  Clipwise/Views/Editor/TextEditorPane.swift
  Clipwise/Views/Editor/ImageEditorPane.swift
  Clipwise/Views/Editor/ImageCanvasView.swift
  Clipwise/Views/Editor/EditorToolbarView.swift
  Tests/ImageTransformServiceTests.swift
  Tests/AnnotationRendererTests.swift
  Tests/ItemEditServiceTests.swift
  Tests/ImageEditorDocumentTests.swift

Modify:
  Clipwise/Models/ClipboardItem.swift      — isEditable, generateHash overload
  Clipwise/App/AppState.swift              — onOpenEditor, editItem(at:), itemEditService
  Clipwise/App/AppDelegate.swift           — own EditorWindowController, wire onOpenEditor
  Clipwise/Views/Panel/ClipboardRowView.swift   — hover pencil button
  Clipwise/Views/Panel/ClipboardListView.swift  — context-menu Edit, button callback
  Clipwise/Views/Panel/PanelContentView.swift   — route onEdit
  Clipwise/Views/Panel/SearchFieldView.swift    — Cmd+E
  Clipwise/Utilities/Constants.swift        — editor window metrics
  project.yml                               — ClipwiseTests target + scheme
```

`xcodegen generate` must be run after adding the files.

## 9. Testing

The repo has no test target. Add one — the pure logic here (pixel geometry, hash
regeneration, SwiftData content replacement) is both the easiest to get subtly
wrong and the easiest to test.

```yaml
# project.yml
  ClipwiseTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: Clipwise

schemes:
  Clipwise:
    build:
      targets: { Clipwise: all }
    test:
      targets: [ClipwiseTests]
```

### Unit tests

- `ImageTransformService` — crop returns the requested pixel region (verified by
  sampling colors of a synthetic quadrant image); rotate 90° swaps dimensions and
  moves a known corner; flip mirrors a known corner; resize returns exact
  dimensions.
- `AnnotationRenderer.flatten` — output pixel size equals `document.pixelSize`;
  a filled rectangle annotation lands on the expected pixels in the expected
  color; an empty annotation list round-trips the base image unchanged.
- `ItemEditService` — against an in-memory `ModelContainer`:
  overwrite preserves `id` / `isPinned` / `firstCopiedAt` and replaces contents;
  copy leaves the original intact and inserts one new item; contents carry the
  expected UTType identifiers; `contentHash` changes when content changes.
- `ImageEditorDocument` — undo restores the previous state; redo reapplies it; a new
  mutation clears the redo stack; the stack caps at 30.

### Manual checklist (UI, not unit-testable)

1. Hover a text row → pencil appears; click it → panel hides, editor opens.
2. Click a row body → still pastes immediately (no regression).
3. `Cmd+E` on the selected row opens the editor.
4. Edit text → Save → panel shows updated title; paste yields new text.
5. Edit text → Save as Copy → both rows present.
6. Draw with each tool, resize the window → annotations stay locked to the image.
7. Redact a region → saved PNG has the region pixelated.
8. Crop, rotate, flip, resize → undo restores the previous state.
9. Close with unsaved changes → alert appears and each button behaves.
10. Edit an item whose original had RTF → pasting into Pages yields the new text,
    not the pre-edit content.
