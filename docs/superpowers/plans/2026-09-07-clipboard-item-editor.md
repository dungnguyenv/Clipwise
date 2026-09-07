# Clipboard Item Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user open a clipboard history item in an editor — plain text, or an image with drawing/annotation tools — and write the result back to history as either an overwrite or a new copy.

**Architecture:** The image editor keeps the base `NSImage` plus an array of vector `ImageAnnotation` values. A single `AnnotationRenderer.draw` function feeds both the live SwiftUI `Canvas` and the `ImageRenderer`-based export, so preview and saved output cannot drift apart. Undo/redo is snapshot push/pop over that array. Geometric transforms (crop/rotate/flip/resize) flatten annotations into the base image first. The editor lives in its own resizable `NSWindow` because `FloatingPanel` dismisses itself on `resignKey`.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `GraphicsContext`, `ImageRenderer`), AppKit (`NSWindow`, `NSAlert`, `NSBitmapImageRep`), Core Graphics, Core Image (`CIPixellate`), SwiftData, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-07-clipboard-item-editor-design.md`

## Global Constraints

- Deployment target macOS 14.0; `SWIFT_VERSION` 5.9. No SPM dependencies — Apple system frameworks only.
- **Do not change any `@Model` stored property.** Adding/removing/renaming one triggers `SwiftDataError.loadIssueModelContainer` and `StorageManager` recovers by deleting the store, so the user loses their whole history. Computed properties and static functions on `@Model` types are safe.
- When replacing an item's contents, delete each `ClipboardItemContent` individually with `context.delete(content)` in a loop. `context.delete(model:)` does not reliably cascade here.
- Never put `@Attribute(.externalStorage)` on `ClipboardItemContent.value` — it makes `value` read back as `nil`.
- All services, state, and views are `@MainActor`-isolated. `NSPasteboard`, `NSStatusItem`, `ModelContext`, and AppKit all require the main thread.
- Max 10 MB per stored representation (`Constants.maxContentSize`, introduced in Task 1).
- Run `xcodegen generate` after adding or removing any file, or after editing `project.yml`.
- Click-to-paste on a row (`ClipboardListView.swift:23-26`) must keep working unchanged. It is the app's primary interaction.

**Build:**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build 2>&1 | tail -20
```

**Test:**

```bash
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

**Run** (never use Xcode Run when touching paste — rebuilding invalidates the Accessibility grant):

```bash
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app
```

---

### Task 1: Test target, shared constants, and `ClipboardItem` editing helpers

Nothing here is user-visible. It exists so every later task has a place to put tests and a single source of truth for the size cap.

**Files:**
- Modify: `project.yml`
- Modify: `Clipwise/Utilities/Constants.swift`
- Modify: `Clipwise/Services/ClipboardMonitor.swift:19` (drop the private cap, use `Constants`)
- Modify: `Clipwise/Models/ClipboardItem.swift`
- Modify: `Clipwise/App/AppDelegate.swift:12` (skip app setup under XCTest)
- Test: `Tests/ClipboardItemTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Constants.maxContentSize: Int` = `10_000_000`
  - `ClipboardItem.isEditable: Bool`
  - `static ClipboardItem.generateHash(from representations: [(type: String, data: Data)]) -> String`
  - `static ClipboardItem.generateTitle(forText text: String) -> String`
  - A runnable `ClipwiseTests` bundle.

- [ ] **Step 1: Add the test target to `project.yml`**

Append to the `targets:` map (sibling of `Clipwise:`), then add a top-level `schemes:` block:

```yaml
  ClipwiseTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: Clipwise
    settings:
      base:
        GENERATE_INFOPLIST_FILE: true
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"

schemes:
  Clipwise:
    build:
      targets:
        Clipwise: all
        ClipwiseTests: [test]
    test:
      targets:
        - ClipwiseTests
```

- [ ] **Step 2: Stop the real app from booting during tests**

The test bundle is hosted by the app, so `applicationDidFinishLaunching` would register global hotkeys and start the 0.5s pasteboard poll while tests run. Guard it. In `Clipwise/App/AppDelegate.swift`, make this the first line of `applicationDidFinishLaunching`:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host inside this app. Booting the status item, hotkeys and
        // clipboard poll during a test run is both pointless and disruptive.
        guard NSClassFromString("XCTestCase") == nil else { return }

        appState = AppState()
```

- [ ] **Step 3: Move the content size cap into `Constants`**

In `Clipwise/Utilities/Constants.swift`, add below `pollingInterval`:

```swift
    /// Max stored bytes per pasteboard representation (10MB).
    static let maxContentSize = 10_000_000
```

In `Clipwise/Services/ClipboardMonitor.swift`, delete these two lines:

```swift
    /// Max data size per content type (10MB)
    private static let maxContentSize = 10_000_000
```

and change the guard in `processPasteboardItems` from `Self.maxContentSize` to:

```swift
                guard data.count < Constants.maxContentSize else { continue }
```

- [ ] **Step 4: Write the failing tests**

Create `Tests/ClipboardItemTests.swift`:

```swift
import XCTest
@testable import Clipwise

final class ClipboardItemTests: XCTestCase {

    func testGenerateHashIsDeterministic() {
        let representations = [(type: "public.utf8-plain-text", data: Data("hello".utf8))]
        XCTAssertEqual(
            ClipboardItem.generateHash(from: representations),
            ClipboardItem.generateHash(from: representations)
        )
    }

    func testGenerateHashChangesWhenContentChanges() {
        let before = [(type: "public.utf8-plain-text", data: Data("hello".utf8))]
        let after = [(type: "public.utf8-plain-text", data: Data("hello!".utf8))]
        XCTAssertNotEqual(
            ClipboardItem.generateHash(from: before),
            ClipboardItem.generateHash(from: after)
        )
    }

    func testGenerateHashIsSHA256Hex() {
        let hash = ClipboardItem.generateHash(from: [(type: "t", data: Data("x".utf8))])
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testGenerateTitleUsesFirstNonEmptyLine() {
        XCTAssertEqual(ClipboardItem.generateTitle(forText: "\n\n  first\nsecond"), "first")
    }

    func testGenerateTitleCapsAtMaxTitleLength() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(
            ClipboardItem.generateTitle(forText: long).count,
            Constants.maxTitleLength
        )
    }

    func testGenerateTitleFallsBackForEmptyText() {
        XCTAssertEqual(ClipboardItem.generateTitle(forText: "   \n  "), "Unknown")
    }
}
```

- [ ] **Step 5: Regenerate the project and run the tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `type 'ClipboardItem' has no member 'generateTitle(forText:)'` and no matching `generateHash` overload.

- [ ] **Step 6: Implement the helpers**

In `Clipwise/Models/ClipboardItem.swift`, add a new section after the `// MARK: - Hash Generation` block's existing functions:

```swift
    // MARK: - Editing

    /// Only text and image items can be opened in the editor (v1).
    var isEditable: Bool {
        primaryType == .text || primaryType == .image
    }

    /// Hash for content assembled by the editor rather than read from a pasteboard.
    /// Same SHA256-hex format as `generateHash(from: [NSPasteboardItem])`.
    static func generateHash(from representations: [(type: String, data: Data)]) -> String {
        var hasher = SHA256()
        for representation in representations {
            hasher.update(data: representation.data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Title rule shared by capture and editing: first non-empty line, capped.
    static func generateTitle(forText text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return String(firstLine.prefix(Constants.maxTitleLength))
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 6 tests passing.

- [ ] **Step 8: Commit**

```bash
git add project.yml Tests/ClipboardItemTests.swift Clipwise/Utilities/Constants.swift \
        Clipwise/Services/ClipboardMonitor.swift Clipwise/Models/ClipboardItem.swift \
        Clipwise/App/AppDelegate.swift Clipwise.xcodeproj
git commit -m "test: add ClipwiseTests target and ClipboardItem editing helpers"
```

---

### Task 2: `ItemEditService` — write edited content back to SwiftData

**Files:**
- Modify: `Clipwise/Extensions/NSImage+Extensions.swift`
- Modify: `Clipwise/Services/StorageManager.swift:9-29` (injectable in-memory store)
- Create: `Clipwise/Services/ItemEditService.swift`
- Test: `Tests/ItemEditServiceTests.swift`

**Interfaces:**
- Consumes: `Constants.maxContentSize`, `ClipboardItem.generateHash(from:)`, `ClipboardItem.generateTitle(forText:)`, `ClipboardItem.isEditable` (Task 1).
- Produces:
  - `NSImage.bitmapRep: NSBitmapImageRep?`
  - `NSImage.pixelSize: CGSize`
  - `NSImage.pngData() -> Data?`
  - `StorageManager.init(inMemory: Bool = false)`
  - `ItemEditService.SaveMode` (`.overwrite` / `.copy`)
  - `ItemEditService.EditError` (`.encodingFailed` / `.tooLarge(bytes:)`)
  - `ItemEditService.init(storageManager:)`
  - `@discardableResult func save(text: String, for: ClipboardItem, mode: SaveMode) throws -> ClipboardItem`
  - `@discardableResult func save(image: NSImage, for: ClipboardItem, mode: SaveMode) throws -> ClipboardItem`

- [ ] **Step 1: Add the NSImage pixel helpers**

Append to `Clipwise/Extensions/NSImage+Extensions.swift`:

```swift
extension NSImage {
    /// The largest bitmap representation, rasterizing first if the image is
    /// vector-backed. Everything pixel-exact goes through this.
    var bitmapRep: NSBitmapImageRep? {
        let bitmaps = representations.compactMap { $0 as? NSBitmapImageRep }
        if let largest = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
            return largest
        }
        guard let tiff = tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    /// Native pixel dimensions. `size` is in points, so on a Retina screenshot
    /// it reports half the real resolution — never use it for pixel math.
    var pixelSize: CGSize {
        guard let rep = bitmapRep else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    func pngData() -> Data? {
        bitmapRep?.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 2: Make `StorageManager` support an in-memory store**

Tests must not touch the user's real store. In `Clipwise/Services/StorageManager.swift` change the initializer signature and config:

```swift
    init(inMemory: Bool = false) {
        let schema = Schema([ClipboardItem.self, ClipboardItemContent.self])
        let config = ModelConfiguration(
            "Clipwise",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
```

Leave the rest of `init` (the do/catch recovery) exactly as it is.

- [ ] **Step 3: Write the failing tests**

Create `Tests/ItemEditServiceTests.swift`:

```swift
import AppKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

@MainActor
final class ItemEditServiceTests: XCTestCase {

    private func makeStorage() -> StorageManager {
        StorageManager(inMemory: true)
    }

    private func makeTextItem(_ text: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(
            title: text,
            sourceAppBundleID: "com.example.source",
            sourceAppName: "Source",
            contentHash: "original-hash"
        )
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    private func makeImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    func testOverwriteKeepsIdentityAndReplacesContent() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        item.isPinned = true
        let id = item.id
        let firstCopiedAt = item.firstCopiedAt

        try service.save(text: "after", for: item, mode: .overwrite)

        XCTAssertEqual(item.id, id)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.firstCopiedAt, firstCopiedAt)
        XCTAssertEqual(item.plainText, "after")
        XCTAssertEqual(item.title, "after")
        XCTAssertNotEqual(item.contentHash, "original-hash")
        XCTAssertEqual(storage.fetchAll().count, 1)
    }

    func testCopyLeavesOriginalIntact() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)

        let copy = try service.save(text: "after", for: item, mode: .copy)

        XCTAssertEqual(item.plainText, "before")
        XCTAssertEqual(copy.plainText, "after")
        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.sourceAppName, "Source", "the copy keeps the original's provenance")
        XCTAssertEqual(storage.fetchAll().count, 2)
    }

    func testTextSaveWritesBothPlainTextTypes() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)

        try service.save(text: "after", for: item, mode: .overwrite)

        let types = Set(item.contents.map(\.type))
        XCTAssertEqual(types, [UTType.utf8PlainText.identifier, UTType.plainText.identifier])
    }

    func testTextSaveDropsStaleRichTextRepresentations() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("before", in: storage)
        item.contents.append(
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("stale rtf".utf8))
        )
        try storage.context.save()

        try service.save(text: "after", for: item, mode: .overwrite)

        XCTAssertFalse(item.contents.contains { $0.type == UTType.rtf.identifier })
    }

    func testImageSaveWritesPNG() throws {
        let storage = makeStorage()
        let service = ItemEditService(storageManager: storage)
        let item = makeTextItem("placeholder", in: storage)

        try service.save(image: makeImage(width: 8, height: 4), for: item, mode: .overwrite)

        let png = item.contents.first { $0.type == UTType.png.identifier }
        XCTAssertNotNil(png?.value)
        XCTAssertEqual(item.title, "Image")
        XCTAssertEqual(NSImage(data: png!.value!)?.pixelSize, CGSize(width: 8, height: 4))
    }

    func testIsEditableRejectsFileItems() throws {
        let storage = makeStorage()
        let item = ClipboardItem(title: "file", contentHash: "h")
        item.contents = [
            ClipboardItemContent(
                type: UTType.fileURL.identifier,
                value: Data("file:///tmp/a.txt".utf8)
            )
        ]
        storage.context.insert(item)

        XCTAssertFalse(item.isEditable)
    }

    func testIsEditableAcceptsTextItems() throws {
        let storage = makeStorage()
        let item = makeTextItem("hello", in: storage)
        XCTAssertTrue(item.isEditable)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'ItemEditService' in scope`.

- [ ] **Step 5: Implement `ItemEditService`**

Create `Clipwise/Services/ItemEditService.swift`:

```swift
import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Writes editor output back into clipboard history.
@MainActor
final class ItemEditService {

    enum SaveMode {
        /// Replace the existing item's content, keeping its identity.
        case overwrite
        /// Insert a new item, leaving the original untouched.
        case copy
    }

    enum EditError: LocalizedError {
        case encodingFailed
        case tooLarge(bytes: Int)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Could not encode the edited content."
            case .tooLarge(let bytes):
                let actual = Double(bytes) / 1_000_000
                let limit = Constants.maxContentSize / 1_000_000
                return String(
                    format: "The edited image is %.1f MB, over the %d MB history limit. Use the Resize tool to shrink it.",
                    actual, limit
                )
            }
        }
    }

    private let storageManager: StorageManager

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
    }

    @discardableResult
    func save(text: String, for item: ClipboardItem, mode: SaveMode) throws -> ClipboardItem {
        let data = Data(text.utf8)
        // Rich-text representations are deliberately dropped: PasteService replays
        // every stored type, so a stale RTF blob would paste the pre-edit content.
        let representations = [
            (type: UTType.utf8PlainText.identifier, data: data),
            (type: UTType.plainText.identifier, data: data),
        ]
        return apply(
            representations: representations,
            title: ClipboardItem.generateTitle(forText: text),
            to: item,
            mode: mode
        )
    }

    @discardableResult
    func save(image: NSImage, for item: ClipboardItem, mode: SaveMode) throws -> ClipboardItem {
        guard let png = image.pngData() else { throw EditError.encodingFailed }
        guard png.count <= Constants.maxContentSize else { throw EditError.tooLarge(bytes: png.count) }

        var representations = [(type: UTType.png.identifier, data: png)]
        // Some older apps only read TIFF off the pasteboard. Skip it silently
        // rather than failing the whole save when it blows the cap.
        if let tiff = image.tiffRepresentation, tiff.count <= Constants.maxContentSize {
            representations.append((type: UTType.tiff.identifier, data: tiff))
        }
        return apply(representations: representations, title: "Image", to: item, mode: mode)
    }

    // MARK: - Private

    private func apply(
        representations: [(type: String, data: Data)],
        title: String,
        to item: ClipboardItem,
        mode: SaveMode
    ) -> ClipboardItem {
        let hash = ClipboardItem.generateHash(from: representations)
        let newContents = representations.map { ClipboardItemContent(type: $0.type, value: $0.data) }

        let target: ClipboardItem
        switch mode {
        case .overwrite:
            let stale = item.contents
            item.contents = newContents
            // Delete each content individually — delete(model:) does not cascade here.
            for content in stale {
                storageManager.context.delete(content)
            }
            item.title = title
            item.contentHash = hash
            item.lastCopiedAt = Date()
            target = item

        case .copy:
            let copy = ClipboardItem(
                title: title,
                sourceAppBundleID: item.sourceAppBundleID,
                sourceAppName: item.sourceAppName,
                contentHash: hash
            )
            copy.contents = newContents
            storageManager.context.insert(copy)
            target = copy
        }

        do {
            try storageManager.context.save()
        } catch {
            NSLog("[Clipwise] Failed to save edited item: \(error)")
        }
        return target
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 8 new tests passing.

- [ ] **Step 7: Commit**

```bash
git add Clipwise/Services/ItemEditService.swift Clipwise/Services/StorageManager.swift \
        Clipwise/Extensions/NSImage+Extensions.swift Tests/ItemEditServiceTests.swift Clipwise.xcodeproj
git commit -m "feat: add ItemEditService for writing edited items back to history"
```

---

### Task 3: `ImageTransformService` — crop, rotate, flip, resize, pixelate

Everything goes through `CGContext`, never `NSImage.lockFocus`, so results are pixel-exact and independent of the screen's backing scale.

**Files:**
- Modify: `Clipwise/Extensions/NSImage+Extensions.swift`
- Create: `Clipwise/Services/ImageTransformService.swift`
- Test: `Tests/ImageTransformServiceTests.swift`

**Interfaces:**
- Consumes: `NSImage.bitmapRep`, `NSImage.pixelSize` (Task 2).
- Produces:
  - `NSImage.cgImageAtNativeSize() -> CGImage?`
  - `ImageTransformService.crop(_ image: NSImage, to rect: CGRect) -> NSImage?` — `rect` is **top-left origin, image pixels**
  - `ImageTransformService.rotate(_ image: NSImage, degrees: CGFloat) -> NSImage?` — `+90` counter-clockwise, `-90` clockwise
  - `ImageTransformService.flip(_ image: NSImage, horizontal: Bool) -> NSImage?`
  - `ImageTransformService.resize(_ image: NSImage, to size: CGSize) -> NSImage?`
  - `ImageTransformService.pixelated(_ image: NSImage, blockSize: CGFloat? = nil) -> NSImage?`

- [ ] **Step 1: Add the native-size CGImage accessor**

Append to the `extension NSImage` block in `Clipwise/Extensions/NSImage+Extensions.swift`:

```swift
    /// The backing CGImage at native pixel dimensions.
    func cgImageAtNativeSize() -> CGImage? {
        if let cgImage = bitmapRep?.cgImage { return cgImage }
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
```

- [ ] **Step 2: Write the failing tests**

The test image is a 40×20 bitmap split into four quadrants — top-left red, top-right green, bottom-left blue, bottom-right yellow. Assertions check *which quadrant* a pixel came from by dominant channel, which is immune to colour-space drift between deviceRGB and sRGB.

Create `Tests/ImageTransformServiceTests.swift`:

```swift
import AppKit
import XCTest
@testable import Clipwise

@MainActor
final class ImageTransformServiceTests: XCTestCase {

    private enum Quadrant: String {
        case red, green, blue, yellow, other
    }

    /// 40x20, quadrants: TL red, TR green, BL blue, BR yellow.
    /// `NSBitmapImageRep.setColor(_:atX:y:)` uses a top-left origin, matching
    /// the annotation coordinate space.
    private func makeQuadrantImage(width: Int = 40, height: Int = 20) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<height {
            for x in 0..<width {
                let isLeft = x < width / 2
                let isTop = y < height / 2
                let color: NSColor
                switch (isTop, isLeft) {
                case (true, true):   color = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
                case (true, false):  color = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
                case (false, true):  color = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
                case (false, false): color = NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1)
                }
                rep.setColor(color, atX: x, y: y)
            }
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func quadrant(of image: NSImage, x: Int, y: Int) -> Quadrant {
        guard let rep = image.bitmapRep,
              let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
        else { return .other }
        let r = color.redComponent > 0.5
        let g = color.greenComponent > 0.5
        let b = color.blueComponent > 0.5
        switch (r, g, b) {
        case (true, false, false): return .red
        case (false, true, false): return .green
        case (false, false, true): return .blue
        case (true, true, false):  return .yellow
        default: return .other
        }
    }

    func testCropReturnsTopLeftQuadrant() throws {
        let cropped = try XCTUnwrap(
            ImageTransformService.crop(makeQuadrantImage(), to: CGRect(x: 0, y: 0, width: 20, height: 10))
        )
        XCTAssertEqual(cropped.pixelSize, CGSize(width: 20, height: 10))
        XCTAssertEqual(quadrant(of: cropped, x: 2, y: 2), .red)
        XCTAssertEqual(quadrant(of: cropped, x: 17, y: 7), .red)
    }

    func testCropReturnsBottomRightQuadrant() throws {
        let cropped = try XCTUnwrap(
            ImageTransformService.crop(makeQuadrantImage(), to: CGRect(x: 20, y: 10, width: 20, height: 10))
        )
        XCTAssertEqual(quadrant(of: cropped, x: 10, y: 5), .yellow)
    }

    func testCropRejectsRectOutsideImage() {
        XCTAssertNil(
            ImageTransformService.crop(makeQuadrantImage(), to: CGRect(x: 100, y: 100, width: 10, height: 10))
        )
    }

    func testRotateCounterClockwiseSwapsDimensionsAndMovesTopLeftToBottomLeft() throws {
        let rotated = try XCTUnwrap(ImageTransformService.rotate(makeQuadrantImage(), degrees: 90))
        XCTAssertEqual(rotated.pixelSize, CGSize(width: 20, height: 40))
        // Rotating CCW sends the original top-left (red) quadrant to the bottom-left.
        XCTAssertEqual(quadrant(of: rotated, x: 5, y: 30), .red)
        XCTAssertEqual(quadrant(of: rotated, x: 15, y: 30), .blue)
    }

    func testFlipHorizontalMirrorsQuadrants() throws {
        let flipped = try XCTUnwrap(ImageTransformService.flip(makeQuadrantImage(), horizontal: true))
        XCTAssertEqual(flipped.pixelSize, CGSize(width: 40, height: 20))
        XCTAssertEqual(quadrant(of: flipped, x: 5, y: 5), .green)
        XCTAssertEqual(quadrant(of: flipped, x: 35, y: 5), .red)
    }

    func testFlipVerticalMirrorsQuadrants() throws {
        let flipped = try XCTUnwrap(ImageTransformService.flip(makeQuadrantImage(), horizontal: false))
        XCTAssertEqual(quadrant(of: flipped, x: 5, y: 5), .blue)
        XCTAssertEqual(quadrant(of: flipped, x: 5, y: 15), .red)
    }

    func testResizeProducesExactDimensionsAndKeepsLayout() throws {
        let resized = try XCTUnwrap(
            ImageTransformService.resize(makeQuadrantImage(), to: CGSize(width: 80, height: 40))
        )
        XCTAssertEqual(resized.pixelSize, CGSize(width: 80, height: 40))
        XCTAssertEqual(quadrant(of: resized, x: 10, y: 10), .red)
        XCTAssertEqual(quadrant(of: resized, x: 70, y: 30), .yellow)
    }

    func testPixelatedPreservesDimensions() throws {
        let pixelated = try XCTUnwrap(ImageTransformService.pixelated(makeQuadrantImage()))
        XCTAssertEqual(pixelated.pixelSize, CGSize(width: 40, height: 20))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'ImageTransformService' in scope`.

- [ ] **Step 4: Implement `ImageTransformService`**

Create `Clipwise/Services/ImageTransformService.swift`:

```swift
import AppKit
import CoreImage

/// Pixel-exact image transforms.
///
/// Rects are in **image pixel space with a top-left origin**, matching
/// `ImageAnnotation` coordinates. CGContext is bottom-left, so every function
/// that takes a rect flips it explicitly.
enum ImageTransformService {

    static func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let target = rect.integral.intersection(bounds)
        guard !target.isNull, target.width >= 1, target.height >= 1 else { return nil }

        return render(width: Int(target.width), height: Int(target.height)) { context in
            // Offset the full image so `target` lands at the context origin.
            context.draw(cgImage, in: CGRect(
                x: -target.origin.x,
                y: -(bounds.height - target.origin.y - target.height),
                width: bounds.width,
                height: bounds.height
            ))
        }
    }

    /// `+90` rotates counter-clockwise, `-90` clockwise. Only right angles.
    static func rotate(_ image: NSImage, degrees: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        return render(width: cgImage.height, height: cgImage.width) { context in
            context.translateBy(x: height / 2, y: width / 2)
            context.rotate(by: degrees * .pi / 180)
            context.draw(cgImage, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
    }

    static func flip(_ image: NSImage, horizontal: Bool) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        return render(width: cgImage.width, height: cgImage.height) { context in
            if horizontal {
                context.translateBy(x: width, y: 0)
                context.scaleBy(x: -1, y: 1)
            } else {
                context.translateBy(x: 0, y: height)
                context.scaleBy(x: 1, y: -1)
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func resize(_ image: NSImage, to size: CGSize) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())

        return render(width: width, height: height) { context in
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
    }

    /// Used by redact annotations. `blockSize` defaults to 1/40th of the
    /// smaller dimension, never below 8px.
    static func pixelated(_ image: NSImage, blockSize: CGFloat? = nil) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let extent = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let scale = blockSize ?? max(8, min(extent.width, extent.height) / 40)

        guard let filter = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: CIImage(cgImage: cgImage),
            kCIInputScaleKey: scale,
            kCIInputCenterKey: CIVector(x: 0, y: 0),
        ]), let output = filter.outputImage,
            let result = CIContext(options: nil).createCGImage(output, from: extent)
        else { return nil }

        return makeImage(from: result, width: cgImage.width, height: cgImage.height)
    }

    // MARK: - Private

    private static func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> NSImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        body(context)

        guard let output = context.makeImage() else { return nil }
        return makeImage(from: output, width: width, height: height)
    }

    /// Wraps a CGImage in an NSImage that carries a real NSBitmapImageRep, so
    /// `NSImage.pixelSize` and `pngData()` report native pixels.
    private static func makeImage(from cgImage: CGImage, width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 8 new tests passing.

If `testRotateCounterClockwiseSwapsDimensionsAndMovesTopLeftToBottomLeft` fails on the quadrant assertion (not the dimensions), the rotation direction convention is inverted — flip the sign in `rotate` and swap the two expected quadrants in the test so the test still pins one concrete direction.

- [ ] **Step 6: Commit**

```bash
git add Clipwise/Services/ImageTransformService.swift Clipwise/Extensions/NSImage+Extensions.swift \
        Tests/ImageTransformServiceTests.swift Clipwise.xcodeproj
git commit -m "feat: add ImageTransformService for crop/rotate/flip/resize/pixelate"
```

---

### Task 4: `ImageAnnotation` and `AnnotationRenderer`

The single drawing function that both the live canvas and the export path call. This is the whole reason the vector model was chosen — there is only one implementation, so preview and saved output cannot disagree.

**Files:**
- Create: `Clipwise/Models/ImageAnnotation.swift`
- Create: `Clipwise/Services/AnnotationRenderer.swift`
- Test: `Tests/AnnotationRendererTests.swift`

**Interfaces:**
- Consumes: `NSImage.pixelSize`, `NSImage.bitmapRep` (Task 2).
- Produces:
  - `enum EditorTool: String, CaseIterable, Identifiable` — cases `pen, highlighter, arrow, rectangle, ellipse, text, redact, crop`; properties `systemImage: String`, `label: String`
  - `struct ImageAnnotation: Identifiable, Equatable` — `init(id: UUID = UUID(), kind: Kind, color: Color, lineWidth: CGFloat)`
  - `ImageAnnotation.Kind` — `.stroke(points: [CGPoint], highlight: Bool)`, `.arrow(from: CGPoint, to: CGPoint)`, `.rectangle(CGRect)`, `.ellipse(CGRect)`, `.text(String, origin: CGPoint, fontSize: CGFloat)`, `.redact(CGRect)`
  - `AnnotationRenderer.draw(annotations:pixelatedBase:in:imageSize:)`
  - `@MainActor AnnotationRenderer.flatten(baseImage:pixelatedBase:annotations:pixelSize:) -> NSImage?`

- [ ] **Step 1: Write the failing tests**

`flatten` with a `.redact` annotation and no pixelated base fills solid black — deterministic, and it pins the top-left origin convention through the entire pipeline.

Create `Tests/AnnotationRendererTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import Clipwise

@MainActor
final class AnnotationRendererTests: XCTestCase {

    private func makeSolidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(color, atX: x, y: y)
            }
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func brightness(of image: NSImage, x: Int, y: Int) -> CGFloat? {
        guard let rep = image.bitmapRep,
              let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }

    func testFlattenWithNoAnnotationsPreservesPixelSize() throws {
        let base = makeSolidImage(width: 40, height: 20, color: .white)
        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [], pixelSize: base.pixelSize
        ))
        XCTAssertEqual(output.pixelSize, CGSize(width: 40, height: 20))
    }

    func testRedactWithoutPixelatedBaseFillsTopLeftRegionBlack() throws {
        let base = makeSolidImage(width: 40, height: 20, color: .white)
        let redact = ImageAnnotation(
            kind: .redact(CGRect(x: 0, y: 0, width: 20, height: 10)),
            color: .black,
            lineWidth: 1
        )

        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [redact], pixelSize: base.pixelSize
        ))

        XCTAssertEqual(output.pixelSize, CGSize(width: 40, height: 20))
        let inside = try XCTUnwrap(brightness(of: output, x: 5, y: 3))
        let outside = try XCTUnwrap(brightness(of: output, x: 35, y: 16))
        XCTAssertLessThan(inside, 0.2, "the redacted top-left region should be dark")
        XCTAssertGreaterThan(outside, 0.8, "the rest of the image should be untouched")
    }

    func testRedactUsesPixelatedBaseWhenProvided() throws {
        let base = makeSolidImage(width: 40, height: 20, color: .white)
        let pixelated = makeSolidImage(
            width: 40, height: 20,
            color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let redact = ImageAnnotation(
            kind: .redact(CGRect(x: 20, y: 10, width: 20, height: 10)),
            color: .black,
            lineWidth: 1
        )

        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: pixelated, annotations: [redact], pixelSize: base.pixelSize
        ))

        let rep = try XCTUnwrap(output.bitmapRep)
        let inside = try XCTUnwrap(rep.colorAt(x: 30, y: 15)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(inside.blueComponent, 0.7)
        XCTAssertLessThan(inside.redComponent, 0.3)
    }

    func testStrokeAnnotationDarkensThePixelsItCovers() throws {
        let base = makeSolidImage(width: 40, height: 20, color: .white)
        let stroke = ImageAnnotation(
            kind: .stroke(points: [CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 10)], highlight: false),
            color: .black,
            lineWidth: 8
        )

        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [stroke], pixelSize: base.pixelSize
        ))

        let onLine = try XCTUnwrap(brightness(of: output, x: 20, y: 10))
        let offLine = try XCTUnwrap(brightness(of: output, x: 20, y: 1))
        XCTAssertLessThan(onLine, 0.2)
        XCTAssertGreaterThan(offLine, 0.8)
    }

    func testEditorToolCasesAllHaveIcons() {
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.systemImage.isEmpty, "\(tool.rawValue) needs an icon")
            XCTAssertFalse(tool.label.isEmpty, "\(tool.rawValue) needs a label")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'ImageAnnotation' in scope`.

- [ ] **Step 3: Create the annotation model**

Create `Clipwise/Models/ImageAnnotation.swift`:

```swift
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case redact
    case crop

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .redact: return "eye.slash"
        case .crop: return "crop"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .redact: return "Redact"
        case .crop: return "Crop"
        }
    }
}

/// One annotation drawn over the base image.
///
/// **All points and rects are in image pixel space with a top-left origin.**
/// Never store view coordinates here — that is what keeps annotations locked to
/// the image when the editor window is resized.
struct ImageAnnotation: Identifiable, Equatable {
    var id = UUID()
    var kind: Kind
    var color: Color
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

- [ ] **Step 4: Create the renderer**

Create `Clipwise/Services/AnnotationRenderer.swift`:

```swift
import AppKit
import SwiftUI

/// The one place annotations turn into pixels. The live canvas and the export
/// path both call `draw`, so what the user sees is what gets saved.
enum AnnotationRenderer {

    /// Draws annotations in image-pixel space. The caller must have scaled
    /// `context` so one unit equals one image pixel.
    static func draw(
        annotations: [ImageAnnotation],
        pixelatedBase: Image?,
        in context: inout GraphicsContext,
        imageSize: CGSize
    ) {
        for annotation in annotations {
            switch annotation.kind {
            case let .stroke(points, highlight):
                drawStroke(points, annotation: annotation, highlight: highlight, in: &context)

            case let .arrow(from, to):
                drawArrow(from: from, to: to, annotation: annotation, in: &context)

            case let .rectangle(rect):
                context.stroke(
                    Path(rect),
                    with: .color(annotation.color),
                    style: StrokeStyle(lineWidth: annotation.lineWidth, lineJoin: .round)
                )

            case let .ellipse(rect):
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(annotation.color),
                    style: StrokeStyle(lineWidth: annotation.lineWidth)
                )

            case let .text(string, origin, fontSize):
                guard !string.isEmpty else { continue }
                var resolved = context.resolve(
                    Text(string).font(.system(size: fontSize, weight: .semibold))
                )
                resolved.shading = .color(annotation.color)
                context.draw(resolved, at: origin, anchor: .topLeading)

            case let .redact(rect):
                drawRedaction(rect, pixelatedBase: pixelatedBase, imageSize: imageSize, in: &context)
            }
        }
    }

    @MainActor
    static func flatten(
        baseImage: NSImage,
        pixelatedBase: NSImage?,
        annotations: [ImageAnnotation],
        pixelSize: CGSize
    ) -> NSImage? {
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }

        let renderer = ImageRenderer(content: FlattenedImageView(
            baseImage: baseImage,
            pixelatedBase: pixelatedBase,
            annotations: annotations,
            pixelSize: pixelSize
        ))
        renderer.scale = 1

        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: pixelSize.width, height: pixelSize.height)
        let output = NSImage(size: rep.size)
        output.addRepresentation(rep)
        return output
    }

    // MARK: - Private

    private static func drawStroke(
        _ points: [CGPoint],
        annotation: ImageAnnotation,
        highlight: Bool,
        in context: inout GraphicsContext
    ) {
        let shading: GraphicsContext.Shading = .color(
            highlight ? annotation.color.opacity(0.35) : annotation.color
        )

        guard points.count > 1 else {
            // A single click still leaves a dot.
            guard let point = points.first else { return }
            let radius = annotation.lineWidth / 2
            let dot = CGRect(
                x: point.x - radius, y: point.y - radius,
                width: radius * 2, height: radius * 2
            )
            context.fill(Path(ellipseIn: dot), with: shading)
            return
        }

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let style = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)

        if highlight {
            context.drawLayer { layer in
                layer.blendMode = .multiply
                layer.stroke(path, with: shading, style: style)
            }
        } else {
            context.stroke(path, with: shading, style: style)
        }
    }

    private static func drawArrow(
        from: CGPoint,
        to: CGPoint,
        annotation: ImageAnnotation,
        in context: inout GraphicsContext
    ) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 1 else { return }

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = min(max(annotation.lineWidth * 4, 12), length)

        // Stop the shaft short so it does not poke through the head.
        var shaft = Path()
        shaft.move(to: from)
        shaft.addLine(to: CGPoint(
            x: to.x - cos(angle) * headLength * 0.8,
            y: to.y - sin(angle) * headLength * 0.8
        ))
        context.stroke(
            shaft,
            with: .color(annotation.color),
            style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round)
        )

        let spread = CGFloat.pi / 7
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(
            x: to.x - cos(angle - spread) * headLength,
            y: to.y - sin(angle - spread) * headLength
        ))
        head.addLine(to: CGPoint(
            x: to.x - cos(angle + spread) * headLength,
            y: to.y - sin(angle + spread) * headLength
        ))
        head.closeSubpath()
        context.fill(head, with: .color(annotation.color))
    }

    private static func drawRedaction(
        _ rect: CGRect,
        pixelatedBase: Image?,
        imageSize: CGSize,
        in context: inout GraphicsContext
    ) {
        guard let pixelatedBase else {
            // No pixelated copy available — fall back to a solid block, which
            // still hides the content.
            context.fill(Path(rect), with: .color(.black))
            return
        }
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            layer.draw(pixelatedBase, in: CGRect(origin: .zero, size: imageSize))
        }
    }
}

/// Off-screen view used by `AnnotationRenderer.flatten`. It runs the exact same
/// `draw` call as the live canvas.
private struct FlattenedImageView: View {
    let baseImage: NSImage
    let pixelatedBase: NSImage?
    let annotations: [ImageAnnotation]
    let pixelSize: CGSize

    var body: some View {
        Canvas { context, size in
            context.draw(Image(nsImage: baseImage), in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(
                annotations: annotations,
                pixelatedBase: pixelatedBase.map { Image(nsImage: $0) },
                in: &context,
                imageSize: size
            )
        }
        .frame(width: pixelSize.width, height: pixelSize.height)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 5 new tests passing.

If `ImageRenderer` produces a blank or wrongly-scaled image, that is the fallback path the spec calls out (§5.4): replace `flatten`'s body with a `CGContext`-backed renderer while keeping `draw` as the single source of drawing truth. Do not duplicate the drawing logic.

- [ ] **Step 6: Commit**

```bash
git add Clipwise/Models/ImageAnnotation.swift Clipwise/Services/AnnotationRenderer.swift \
        Tests/AnnotationRendererTests.swift Clipwise.xcodeproj
git commit -m "feat: add vector annotation model and shared renderer"
```

---

### Task 5: `ImageEditorDocument` — mutable state, undo/redo, transforms

**Files:**
- Create: `Clipwise/Models/ImageEditorDocument.swift`
- Test: `Tests/ImageEditorDocumentTests.swift`

**Interfaces:**
- Consumes: `AnnotationRenderer.flatten(...)`, `ImageAnnotation` (Task 4); `ImageTransformService.pixelated(_:blockSize:)` (Task 3); `NSImage.pixelSize` (Task 2).
- Produces:
  - `@MainActor @Observable final class ImageEditorDocument`
  - `init(baseImage: NSImage)`
  - `private(set) var baseImage: NSImage`, `private(set) var annotations: [ImageAnnotation]`, `private(set) var hasUnsavedChanges: Bool`
  - `var pixelSize: CGSize`, `var pixelatedBase: NSImage?`, `var canUndo: Bool`, `var canRedo: Bool`
  - `func add(_ annotation: ImageAnnotation)`
  - `func applyTransform(_ transform: (NSImage) -> NSImage?)`
  - `func undo()`, `func redo()`, `func flattened() -> NSImage?`
  - `static let undoLimit = 30`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ImageEditorDocumentTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import Clipwise

@MainActor
final class ImageEditorDocumentTests: XCTestCase {

    private func makeImage(width: Int = 20, height: Int = 10) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(.white, atX: x, y: y)
            }
        }
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func makeAnnotation(_ index: Int = 0) -> ImageAnnotation {
        ImageAnnotation(
            kind: .rectangle(CGRect(x: CGFloat(index), y: 0, width: 2, height: 2)),
            color: .red,
            lineWidth: 2
        )
    }

    func testStartsClean() {
        let document = ImageEditorDocument(baseImage: makeImage())
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
        XCTAssertEqual(document.pixelSize, CGSize(width: 20, height: 10))
    }

    func testAddMarksDirtyAndEnablesUndo() {
        let document = ImageEditorDocument(baseImage: makeImage())
        document.add(makeAnnotation())

        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertTrue(document.canUndo)
    }

    func testUndoRestoresPreviousState() {
        let document = ImageEditorDocument(baseImage: makeImage())
        document.add(makeAnnotation(1))
        document.add(makeAnnotation(2))

        document.undo()

        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.canRedo)
    }

    func testRedoReappliesUndoneChange() {
        let document = ImageEditorDocument(baseImage: makeImage())
        document.add(makeAnnotation(1))
        document.undo()
        document.redo()

        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertFalse(document.canRedo)
    }

    func testNewChangeClearsRedoStack() {
        let document = ImageEditorDocument(baseImage: makeImage())
        document.add(makeAnnotation(1))
        document.undo()
        XCTAssertTrue(document.canRedo)

        document.add(makeAnnotation(2))

        XCTAssertFalse(document.canRedo)
    }

    func testUndoStackCapsAtLimit() {
        let document = ImageEditorDocument(baseImage: makeImage())
        let total = ImageEditorDocument.undoLimit + 5
        for index in 0..<total {
            document.add(makeAnnotation(index))
        }

        for _ in 0..<ImageEditorDocument.undoLimit {
            document.undo()
        }

        XCTAssertFalse(document.canUndo, "the stack should be exhausted at the limit")
        XCTAssertEqual(
            document.annotations.count, 5,
            "the 5 oldest snapshots were dropped, so undo cannot go below 5 annotations"
        )
    }

    func testApplyTransformFlattensAnnotationsAndSwapsBaseImage() {
        let document = ImageEditorDocument(baseImage: makeImage(width: 20, height: 10))
        document.add(makeAnnotation())

        document.applyTransform { ImageTransformService.resize($0, to: CGSize(width: 40, height: 20)) }

        XCTAssertTrue(document.annotations.isEmpty, "a transform flattens annotations into the base")
        XCTAssertEqual(document.pixelSize, CGSize(width: 40, height: 20))
    }

    func testUndoAfterTransformRestoresOriginalSize() {
        let document = ImageEditorDocument(baseImage: makeImage(width: 20, height: 10))
        document.applyTransform { ImageTransformService.resize($0, to: CGSize(width: 40, height: 20)) }

        document.undo()

        XCTAssertEqual(document.pixelSize, CGSize(width: 20, height: 10))
    }

    func testFailedTransformLeavesDocumentUnchanged() {
        let document = ImageEditorDocument(baseImage: makeImage(width: 20, height: 10))
        document.applyTransform { _ in nil }

        XCTAssertEqual(document.pixelSize, CGSize(width: 20, height: 10))
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertFalse(document.canUndo)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'ImageEditorDocument' in scope`.

- [ ] **Step 3: Implement the document**

Create `Clipwise/Models/ImageEditorDocument.swift`:

```swift
import AppKit
import Observation

/// Mutable state of one open image edit: the base bitmap, the annotations drawn
/// over it, and an undo history.
///
/// Image-only by design. The text pane keeps a plain `String` and inherits undo
/// from the `NSTextView` behind SwiftUI's `TextEditor`.
@MainActor
@Observable
final class ImageEditorDocument {

    static let undoLimit = 30

    private struct Snapshot {
        let baseImage: NSImage
        let annotations: [ImageAnnotation]
    }

    private(set) var baseImage: NSImage
    private(set) var annotations: [ImageAnnotation] = []
    private(set) var hasUnsavedChanges = false

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var cachedPixelatedBase: NSImage?

    init(baseImage: NSImage) {
        self.baseImage = baseImage
    }

    var pixelSize: CGSize { baseImage.pixelSize }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Pixelated copy of the current base image, used to render redactions.
    /// Computed once per base image.
    var pixelatedBase: NSImage? {
        if let cachedPixelatedBase { return cachedPixelatedBase }
        cachedPixelatedBase = ImageTransformService.pixelated(baseImage)
        return cachedPixelatedBase
    }

    // MARK: - Mutations

    func add(_ annotation: ImageAnnotation) {
        checkpoint()
        annotations.append(annotation)
    }

    /// Flattens current annotations into the base image, then applies
    /// `transform` to the result. Any geometric change goes through here — that
    /// is what keeps annotation coordinates meaningful after a crop or rotate.
    func applyTransform(_ transform: (NSImage) -> NSImage?) {
        guard let flattenedImage = flattened(), let transformed = transform(flattenedImage) else { return }
        checkpoint()
        annotations = []
        baseImage = transformed
        cachedPixelatedBase = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        restore(next)
    }

    func flattened() -> NSImage? {
        AnnotationRenderer.flatten(
            baseImage: baseImage,
            pixelatedBase: pixelatedBase,
            annotations: annotations,
            pixelSize: pixelSize
        )
    }

    // MARK: - Private

    private func checkpoint() {
        undoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        hasUnsavedChanges = true
    }

    private func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        cachedPixelatedBase = nil
        hasUnsavedChanges = !undoStack.isEmpty
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 9 new tests passing.

- [ ] **Step 5: Commit**

```bash
git add Clipwise/Models/ImageEditorDocument.swift Tests/ImageEditorDocumentTests.swift Clipwise.xcodeproj
git commit -m "feat: add ImageEditorDocument with snapshot undo/redo"
```

---

### Task 6: `EditorSession` and the editor views

After this task the editor UI exists but nothing opens it yet — Task 7 wires the entry points. The image pane is preview-only here; Tasks 8 and 9 add the canvas and toolbar.

**Files:**
- Create: `Clipwise/Views/Editor/EditorSession.swift`
- Create: `Clipwise/Views/Editor/EditorRootView.swift`
- Create: `Clipwise/Views/Editor/EditorFooterBar.swift`
- Create: `Clipwise/Views/Editor/TextEditorPane.swift`
- Create: `Clipwise/Views/Editor/ImageEditorPane.swift`
- Test: `Tests/EditorSessionTests.swift`

**Interfaces:**
- Consumes: `ItemEditService` (Task 2), `ImageEditorDocument` (Task 5), `ClipboardItem.isEditable`, `.plainText`, `.image`, `.primaryType`.
- Produces:
  - `@MainActor @Observable final class EditorSession`
  - `EditorSession.Mode` — `.text`, `.image`
  - `init?(item: ClipboardItem, editService: ItemEditService)` — returns `nil` for non-editable items
  - `var text: String`, `var errorMessage: String?`, `let document: ImageEditorDocument?`, `let mode: Mode`, `let item: ClipboardItem`
  - `var hasUnsavedChanges: Bool`, `var hasRichTextRepresentation: Bool`
  - `func save(_ target: ItemEditService.SaveMode) -> Bool`
  - `EditorRootView(session:onFinished:onCancel:)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/EditorSessionTests.swift`:

```swift
import AppKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

@MainActor
final class EditorSessionTests: XCTestCase {

    private func makeService() -> (ItemEditService, StorageManager) {
        let storage = StorageManager(inMemory: true)
        return (ItemEditService(storageManager: storage), storage)
    }

    private func makeTextItem(_ text: String, in storage: StorageManager) -> ClipboardItem {
        let item = ClipboardItem(title: text, contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data(text.utf8))
        ]
        storage.context.insert(item)
        try? storage.context.save()
        return item
    }

    func testInitReturnsNilForNonEditableItem() {
        let (service, storage) = makeService()
        let item = ClipboardItem(title: "file", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.fileURL.identifier, value: Data("file:///tmp/a".utf8))
        ]
        storage.context.insert(item)

        XCTAssertNil(EditorSession(item: item, editService: service))
    }

    func testTextSessionStartsCleanAndTracksEdits() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("hello", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        XCTAssertEqual(session.mode, .text)
        XCTAssertEqual(session.text, "hello")
        XCTAssertFalse(session.hasUnsavedChanges)

        session.text = "hello world"
        XCTAssertTrue(session.hasUnsavedChanges)

        session.text = "hello"
        XCTAssertFalse(session.hasUnsavedChanges, "reverting the text clears the dirty flag")
    }

    func testDetectsRichTextRepresentation() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("hello", in: storage)
        let plain = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertFalse(plain.hasRichTextRepresentation)

        item.contents.append(
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("rtf".utf8))
        )
        let rich = try XCTUnwrap(EditorSession(item: item, editService: service))
        XCTAssertTrue(rich.hasRichTextRepresentation)
    }

    func testSaveOverwriteWritesThroughToTheItem() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("before", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.overwrite))

        XCTAssertEqual(item.plainText, "after")
        XCTAssertNil(session.errorMessage)
    }

    func testSaveAsCopyLeavesOriginal() throws {
        let (service, storage) = makeService()
        let item = makeTextItem("before", in: storage)
        let session = try XCTUnwrap(EditorSession(item: item, editService: service))

        session.text = "after"
        XCTAssertTrue(session.save(.copy))

        XCTAssertEqual(item.plainText, "before")
        XCTAssertEqual(storage.fetchAll().count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'EditorSession' in scope`.

- [ ] **Step 3: Implement `EditorSession`**

Create `Clipwise/Views/Editor/EditorSession.swift`:

```swift
import AppKit
import Observation
import UniformTypeIdentifiers

/// State shared between the editor's views and the window that hosts them.
/// `EditorWindowController` reads `hasUnsavedChanges` to decide whether closing
/// needs a confirmation prompt.
@MainActor
@Observable
final class EditorSession {

    enum Mode {
        case text
        case image
    }

    let item: ClipboardItem
    let mode: Mode
    let document: ImageEditorDocument?

    var text: String
    var errorMessage: String?

    private let originalText: String
    private let editService: ItemEditService

    /// Returns `nil` when the item is not editable (file URLs, or an image whose
    /// data failed to decode).
    init?(item: ClipboardItem, editService: ItemEditService) {
        self.item = item
        self.editService = editService

        switch item.primaryType {
        case .image:
            guard let image = item.image else { return nil }
            self.mode = .image
            self.document = ImageEditorDocument(baseImage: image)
            self.text = ""
            self.originalText = ""

        case .text:
            let existing = item.plainText ?? ""
            self.mode = .text
            self.document = nil
            self.text = existing
            self.originalText = existing

        case .fileURL, .rtf, .html:
            return nil
        }
    }

    var hasUnsavedChanges: Bool {
        switch mode {
        case .text: return text != originalText
        case .image: return document?.hasUnsavedChanges ?? false
        }
    }

    /// True when the item carries RTF or HTML that a text save will discard.
    var hasRichTextRepresentation: Bool {
        item.contents.contains { content in
            guard let type = UTType(content.type) else { return false }
            return type.conforms(to: .rtf) || type.conforms(to: .html)
        }
    }

    /// Returns `true` when the save succeeded and the window may close.
    /// On failure `errorMessage` is set for the alert.
    func save(_ target: ItemEditService.SaveMode) -> Bool {
        do {
            switch mode {
            case .text:
                try editService.save(text: text, for: item, mode: target)
            case .image:
                guard let image = document?.flattened() else {
                    errorMessage = "Could not render the edited image."
                    return false
                }
                try editService.save(image: image, for: item, mode: target)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 4: Create the footer bar**

Create `Clipwise/Views/Editor/EditorFooterBar.swift`:

```swift
import SwiftUI

struct EditorFooterBar: View {
    @Bindable var session: EditorSession
    var onFinished: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if session.mode == .text {
                Text("\(session.text.count) characters · \(lineCount) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Save as Copy") {
                if session.save(.copy) { onFinished() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save") {
                if session.save(.overwrite) { onFinished() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var lineCount: Int {
        max(1, session.text.components(separatedBy: .newlines).count)
    }
}
```

- [ ] **Step 5: Create the text pane**

Create `Clipwise/Views/Editor/TextEditorPane.swift`:

```swift
import SwiftUI

struct TextEditorPane: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            if session.hasRichTextRepresentation {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Saving converts this item to plain text — its formatted version is discarded.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            TextEditor(text: $session.text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
    }
}
```

- [ ] **Step 6: Create the image pane (preview only for now)**

Create `Clipwise/Views/Editor/ImageEditorPane.swift`. Task 8 replaces the body with the live canvas and Task 9 adds the toolbar; this version already lets the user open an image and Save as Copy.

```swift
import SwiftUI

struct ImageEditorPane: View {
    @Bindable var session: EditorSession

    var body: some View {
        if let document = session.document {
            Image(nsImage: document.baseImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 7: Create the root view**

Create `Clipwise/Views/Editor/EditorRootView.swift`:

```swift
import SwiftUI

struct EditorRootView: View {
    @Bindable var session: EditorSession
    /// Called after a successful save — the window closes unconditionally.
    var onFinished: () -> Void
    /// Called for Cancel/Esc — routed through the window so the unsaved-changes
    /// guard runs.
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch session.mode {
            case .text:
                TextEditorPane(session: session)
            case .image:
                ImageEditorPane(session: session)
            }

            Divider()

            EditorFooterBar(session: session, onFinished: onFinished, onCancel: onCancel)
        }
        .frame(minWidth: Constants.editorMinWidth, minHeight: Constants.editorMinHeight)
        .alert(
            "Cannot Save",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            ),
            actions: {
                Button("OK") { session.errorMessage = nil }
            },
            message: {
                Text(session.errorMessage ?? "")
            }
        )
    }
}
```

- [ ] **Step 8: Add the editor window metrics to `Constants`**

`EditorRootView` references these, so add them now. In `Clipwise/Utilities/Constants.swift`, below `maxContentSize`:

```swift
    static let editorWindowWidth: CGFloat = 720
    static let editorWindowHeight: CGFloat = 560
    static let editorMinWidth: CGFloat = 520
    static let editorMinHeight: CGFloat = 420
```

- [ ] **Step 9: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 5 new tests passing.

- [ ] **Step 10: Commit**

```bash
git add Clipwise/Views/Editor Clipwise/Utilities/Constants.swift \
        Tests/EditorSessionTests.swift Clipwise.xcodeproj
git commit -m "feat: add EditorSession and editor views (text pane, image preview, footer)"
```

---

### Task 7: Window controller, app wiring, and panel entry points

First end-to-end task: after this, hovering a text row shows a pencil, clicking it opens a real editor window, and Save writes back to history.

**Files:**
- Create: `Clipwise/Views/Editor/EditorWindowController.swift`
- Modify: `Clipwise/App/AppState.swift`
- Modify: `Clipwise/App/AppDelegate.swift`
- Modify: `Clipwise/Views/Panel/ClipboardRowView.swift`
- Modify: `Clipwise/Views/Panel/ClipboardListView.swift`
- Modify: `Clipwise/Views/Panel/PanelContentView.swift`
- Modify: `Clipwise/Views/Panel/SearchFieldView.swift`

**Interfaces:**
- Consumes: `EditorSession`, `EditorRootView` (Task 6); `ItemEditService` (Task 2); `ClipboardItem.isEditable` (Task 1); `Constants.editorWindowWidth/Height/MinWidth/MinHeight` (Task 6).
- Produces:
  - `@MainActor final class EditorWindowController: NSObject, NSWindowDelegate`
  - `init(appState: AppState)`, `func open(_ item: ClipboardItem)`
  - `AppState.itemEditService: ItemEditService`
  - `AppState.onOpenEditor: ((ClipboardItem) -> Void)?`
  - `AppState.editItem(at index: Int)`
  - `ClipboardRowView(item:isSelected:isHovering:onEdit:)`
  - `SearchFieldView(query:onQueryChanged:onEscape:onArrowDown:onArrowUp:onReturn:onEdit:)`

- [ ] **Step 1: Add the edit service and entry point to `AppState`**

In `Clipwise/App/AppState.swift`, add to the stored service list beside `pasteService`:

```swift
    let searchEngine: SearchEngine
    let itemEditService: ItemEditService
```

In `init()`, after `self.searchEngine = SearchEngine()`:

```swift
        self.itemEditService = ItemEditService(storageManager: storage)
```

Next to `var onDismissPanel: (() -> Void)?`, add:

```swift
    var onOpenEditor: ((ClipboardItem) -> Void)?

    func editItem(at index: Int) {
        guard index < filteredItems.count else { return }
        let item = filteredItems[index]
        guard item.isEditable else { return }
        onOpenEditor?(item)
    }
```

- [ ] **Step 2: Create the window controller**

Create `Clipwise/Views/Editor/EditorWindowController.swift`. The unsaved-changes guard arrives in Task 10 — `windows` already stores the session so that step is a pure addition.

```swift
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
            NSLog("[Clipwise] Item \(itemID) is not editable")
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

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        entries = entries.filter { $0.value.window !== window }
    }

    // MARK: - Private

    /// Closes without running the unsaved-changes guard — used after a save,
    /// where there is nothing left to confirm.
    private func forceClose(_ window: NSWindow?) {
        guard let window else { return }
        entries = entries.filter { $0.value.window !== window }
        window.delegate = nil
        window.close()
    }
}
```

- [ ] **Step 3: Wire the controller into `AppDelegate`**

In `Clipwise/App/AppDelegate.swift`, add a stored property beside `settingsWindow`:

```swift
    private var editorWindowController: EditorWindowController!
```

In `applicationDidFinishLaunching`, right after the `appState.onDismissPanel` assignment:

```swift
        editorWindowController = EditorWindowController(appState: appState)
        appState.onOpenEditor = { [weak self] item in
            guard let self else { return }
            // FloatingPanel dismisses itself on resignKey, so hide it first and
            // let the teardown finish — same sequence as opening Settings.
            self.hidePanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.editorWindowController.open(item)
            }
        }
```

- [ ] **Step 4: Add the hover pencil to `ClipboardRowView`**

In `Clipwise/Views/Panel/ClipboardRowView.swift`, add a stored property after `isHovering`:

```swift
    var onEdit: (() -> Void)?
```

Then insert this block in the `HStack` immediately after `Spacer()` and before the `if item.isPinned` block:

```swift
            if item.isEditable, isSelected || isHovering {
                Button {
                    onEdit?()
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                }
                .buttonStyle(.plain)
                .help("Edit")
            }
```

The `Button` consumes the click, so the row's `onTapGesture` paste does not fire.

- [ ] **Step 5: Pass the callback and add the context-menu entry**

In `Clipwise/Views/Panel/ClipboardListView.swift`, change the `ClipboardRowView` construction to:

```swift
                        ClipboardRowView(
                            item: item,
                            isSelected: index == appState.selectedIndex,
                            isHovering: appState.hoveredItemID == item.id,
                            onEdit: { appState.editItem(at: index) }
                        )
```

and make the `.contextMenu` block start with:

```swift
                        .contextMenu {
                            if item.isEditable {
                                Button("Edit") {
                                    appState.editItem(at: index)
                                }
                                Divider()
                            }
                            Button(item.isPinned ? "Unpin" : "Pin") {
```

- [ ] **Step 6: Add the Cmd+E shortcut**

In `Clipwise/Views/Panel/SearchFieldView.swift`, add to the properties:

```swift
    var onEdit: () -> Void
```

and add this modifier on the `TextField`, after `.onKeyPress(.escape)`:

```swift
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          press.characters.lowercased() == "e"
                    else { return .ignored }
                    onEdit()
                    return .handled
                }
```

In `Clipwise/Views/Panel/PanelContentView.swift`, add to the `SearchFieldView` call, after `onReturn`:

```swift
                    onEdit: {
                        appState.editItem(at: appState.selectedIndex)
                    }
```

- [ ] **Step 7: Build and run the app**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app
```

Expected: all existing tests still pass, build succeeds.

- [ ] **Step 8: Verify manually**

Copy some text so history has an entry, then press Cmd+Shift+C and check each of these:

1. Hover a text row → a pencil appears on the right.
2. Click the **row body** (not the pencil) → it still pastes immediately. **This is the regression that matters most.**
3. Click the pencil → panel hides, an "Edit Text" window opens with the text loaded.
4. Change the text → **Save** → window closes, reopen the panel, the row shows the new title, and pasting it yields the new text.
5. Edit again → **Save as Copy** → two rows now, original unchanged.
6. Right-click a row → an **Edit** entry appears above Pin.
7. Select a row with the arrow keys, press **Cmd+E** → the editor opens for that row.
8. Copy an image (e.g. Cmd+Shift+4 a region), hover its row → pencil appears; click it → an "Edit Image" window shows the image.
9. Copy a file in Finder → its row shows **no** pencil and no Edit menu entry.

- [ ] **Step 9: Commit**

```bash
git add Clipwise/Views/Editor/EditorWindowController.swift Clipwise/App/AppState.swift \
        Clipwise/App/AppDelegate.swift Clipwise/Views/Panel Clipwise.xcodeproj
git commit -m "feat: open items in an editor window from hover button, menu, and Cmd+E"
```

---

### Task 8: `ImageCanvasView` — coordinate mapping and drawing

After this task the user can draw on an image with a pen and save the result. The toolbar comes in Task 9.

**Files:**
- Create: `Clipwise/Views/Editor/ImageCanvasView.swift`
- Modify: `Clipwise/Views/Editor/ImageEditorPane.swift`
- Test: `Tests/ImageCanvasGeometryTests.swift`

**Interfaces:**
- Consumes: `ImageEditorDocument` (Task 5), `AnnotationRenderer.draw` / `ImageAnnotation` / `EditorTool` (Task 4).
- Produces:
  - `ImageCanvasView(document:tool:color:lineWidth:cropRect:pendingTextOrigin:pendingText:onCommitText:)`
  - `static ImageCanvasView.fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect`
  - `static ImageCanvasView.imagePoint(from: CGPoint, display: CGRect, scale: CGFloat) -> CGPoint`
  - `static ImageCanvasView.rect(_ a: CGPoint, _ b: CGPoint) -> CGRect`

- [ ] **Step 1: Write the failing tests**

The geometry helpers are pure functions and carry the whole "annotations stay locked to the image" guarantee, so they get real tests.

Create `Tests/ImageCanvasGeometryTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import Clipwise

@MainActor
final class ImageCanvasGeometryTests: XCTestCase {

    func testFittedRectCentersAndPreservesAspectRatio() {
        let display = ImageCanvasView.fittedRect(
            imageSize: CGSize(width: 400, height: 200),
            in: CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(display.width, 200, accuracy: 0.01)
        XCTAssertEqual(display.height, 100, accuracy: 0.01)
        XCTAssertEqual(display.minX, 0, accuracy: 0.01)
        XCTAssertEqual(display.minY, 50, accuracy: 0.01, "letterboxed vertically")
    }

    func testFittedRectNeverUpscalesSmallImages() {
        let display = ImageCanvasView.fittedRect(
            imageSize: CGSize(width: 40, height: 20),
            in: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(display.width, 40, accuracy: 0.01)
        XCTAssertEqual(display.height, 20, accuracy: 0.01)
    }

    func testFittedRectHandlesZeroSizedImage() {
        let display = ImageCanvasView.fittedRect(imageSize: .zero, in: CGSize(width: 100, height: 100))
        XCTAssertEqual(display, .zero)
    }

    func testImagePointRoundTripsThroughTheDisplayRect() {
        let imageSize = CGSize(width: 400, height: 200)
        let display = ImageCanvasView.fittedRect(imageSize: imageSize, in: CGSize(width: 200, height: 200))
        let scale = display.width / imageSize.width

        // Centre of the displayed image maps to the centre of the image.
        let point = ImageCanvasView.imagePoint(
            from: CGPoint(x: display.midX, y: display.midY),
            display: display,
            scale: scale
        )
        XCTAssertEqual(point.x, 200, accuracy: 0.01)
        XCTAssertEqual(point.y, 100, accuracy: 0.01)
    }

    func testImagePointMapsTopLeftCornerToOrigin() {
        let imageSize = CGSize(width: 400, height: 200)
        let display = ImageCanvasView.fittedRect(imageSize: imageSize, in: CGSize(width: 200, height: 200))
        let scale = display.width / imageSize.width

        let point = ImageCanvasView.imagePoint(
            from: CGPoint(x: display.minX, y: display.minY),
            display: display,
            scale: scale
        )
        XCTAssertEqual(point.x, 0, accuracy: 0.01)
        XCTAssertEqual(point.y, 0, accuracy: 0.01)
    }

    func testRectNormalizesDragsInAnyDirection() {
        let dragged = ImageCanvasView.rect(CGPoint(x: 30, y: 40), CGPoint(x: 10, y: 20))
        XCTAssertEqual(dragged, CGRect(x: 10, y: 20, width: 20, height: 20))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'ImageCanvasView' in scope`.

- [ ] **Step 3: Create the canvas**

Create `Clipwise/Views/Editor/ImageCanvasView.swift`:

```swift
import SwiftUI

/// Draws the image and its annotations, and turns pointer drags into
/// annotations in image-pixel space.
struct ImageCanvasView: View {
    let document: ImageEditorDocument
    let tool: EditorTool
    let color: Color
    let lineWidth: CGFloat

    @Binding var cropRect: CGRect?
    @Binding var pendingTextOrigin: CGPoint?
    @Binding var pendingText: String
    var onCommitText: () -> Void

    /// The annotation being dragged right now, not yet committed to the document.
    @State private var draft: ImageAnnotation?
    @State private var dragOrigin: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let display = Self.fittedRect(imageSize: document.pixelSize, in: geometry.size)
            let scale = display.width > 0 ? display.width / document.pixelSize.width : 1

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.draw(Image(nsImage: document.baseImage), in: display)

                    // Everything below is expressed in image pixels.
                    context.translateBy(x: display.minX, y: display.minY)
                    context.scaleBy(x: scale, y: scale)

                    var annotations = document.annotations
                    if let draft { annotations.append(draft) }

                    AnnotationRenderer.draw(
                        annotations: annotations,
                        pixelatedBase: document.pixelatedBase.map { Image(nsImage: $0) },
                        in: &context,
                        imageSize: document.pixelSize
                    )

                    if let cropRect {
                        context.stroke(
                            Path(cropRect),
                            with: .color(.white),
                            style: StrokeStyle(
                                lineWidth: 1 / scale,
                                dash: [6 / scale, 4 / scale]
                            )
                        )
                    }
                }
                .gesture(dragGesture(display: display, scale: scale))

                if let origin = pendingTextOrigin {
                    TextField("Text", text: $pendingText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 180)
                        .position(
                            x: display.minX + origin.x * scale + 90,
                            y: display.minY + origin.y * scale + 12
                        )
                        .onSubmit(onCommitText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Geometry

    /// The image's on-screen rect: aspect-fit and centred, never upscaled.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(
            container.width / imageSize.width,
            container.height / imageSize.height,
            1
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func imagePoint(from viewPoint: CGPoint, display: CGRect, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - display.minX) / scale,
            y: (viewPoint.y - display.minY) / scale
        )
    }

    /// Normalizes a drag into a rect regardless of drag direction.
    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    // MARK: - Gesture

    private func dragGesture(display: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = Self.imagePoint(from: value.location, display: display, scale: scale)
                if dragOrigin == nil {
                    dragOrigin = Self.imagePoint(
                        from: value.startLocation, display: display, scale: scale
                    )
                }
                guard let origin = dragOrigin else { return }

                switch tool {
                case .pen, .highlighter:
                    appendStrokePoint(point, from: origin)

                case .arrow:
                    draft = ImageAnnotation(
                        kind: .arrow(from: origin, to: point),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .rectangle:
                    draft = ImageAnnotation(
                        kind: .rectangle(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .ellipse:
                    draft = ImageAnnotation(
                        kind: .ellipse(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .redact:
                    draft = ImageAnnotation(
                        kind: .redact(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .crop:
                    cropRect = Self.rect(origin, point)

                case .text:
                    break
                }
            }
            .onEnded { value in
                if tool == .text {
                    pendingText = ""
                    pendingTextOrigin = Self.imagePoint(
                        from: value.location, display: display, scale: scale
                    )
                } else if let draft {
                    document.add(draft)
                }
                draft = nil
                dragOrigin = nil
            }
    }

    private func appendStrokePoint(_ point: CGPoint, from origin: CGPoint) {
        if let current = draft, case let .stroke(points, highlight) = current.kind {
            draft?.kind = .stroke(points: points + [point], highlight: highlight)
            return
        }
        let isHighlighter = tool == .highlighter
        draft = ImageAnnotation(
            kind: .stroke(points: [origin, point], highlight: isHighlighter),
            color: color,
            // A highlighter only reads as one if it is fat.
            lineWidth: isHighlighter ? lineWidth * 3 : lineWidth
        )
    }
}
```

- [ ] **Step 4: Wire the canvas into the image pane**

Replace the body of `Clipwise/Views/Editor/ImageEditorPane.swift` with a pen-only version. Task 9 adds the toolbar around it.

```swift
import SwiftUI

struct ImageEditorPane: View {
    @Bindable var session: EditorSession

    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var cropRect: CGRect?
    @State private var pendingTextOrigin: CGPoint?
    @State private var pendingText: String = ""

    var body: some View {
        if let document = session.document {
            ImageCanvasView(
                document: document,
                tool: .pen,
                color: color,
                lineWidth: lineWidth,
                cropRect: $cropRect,
                pendingTextOrigin: $pendingTextOrigin,
                pendingText: $pendingText,
                onCommitText: {}
            )
            .padding(12)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 6 new tests passing.

- [ ] **Step 6: Verify manually**

```bash
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app
```

1. Copy a screenshot, open its editor, drag across the image → a red line follows the pointer.
2. **Resize the window** while drawn lines are present → the lines stay locked to the same spot on the image. This is the coordinate-space guarantee; if they drift, the drag is writing view coordinates instead of image coordinates.
3. **Save as Copy** → a new row appears whose thumbnail shows the drawing.
4. Paste that row into Preview or Notes → the drawing is in the pasted image.

- [ ] **Step 7: Commit**

```bash
git add Clipwise/Views/Editor/ImageCanvasView.swift Clipwise/Views/Editor/ImageEditorPane.swift \
        Tests/ImageCanvasGeometryTests.swift Clipwise.xcodeproj
git commit -m "feat: draw annotations on the image canvas in image-pixel space"
```

---

### Task 9: `EditorToolbarView` — all tools, transforms, undo/redo

**Files:**
- Create: `Clipwise/Views/Editor/EditorToolbarView.swift`
- Modify: `Clipwise/Views/Editor/ImageEditorPane.swift`

**Interfaces:**
- Consumes: `EditorTool` (Task 4), `ImageEditorDocument` (Task 5), `ImageTransformService` (Task 3), `ImageCanvasView` (Task 8).
- Produces: `EditorToolbarView(tool:color:lineWidth:document:onRotate:onFlip:onResize:)`

- [ ] **Step 1: Create the toolbar**

Create `Clipwise/Views/Editor/EditorToolbarView.swift`:

```swift
import SwiftUI

struct EditorToolbarView: View {
    @Binding var tool: EditorTool
    @Binding var color: Color
    @Binding var lineWidth: CGFloat
    let document: ImageEditorDocument

    /// `+90` rotates counter-clockwise, `-90` clockwise.
    var onRotate: (CGFloat) -> Void
    /// `true` flips horizontally, `false` vertically.
    var onFlip: (Bool) -> Void
    var onResize: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(EditorTool.allCases) { item in
                Button {
                    tool = item
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13))
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(tool == item ? Color.accentColor.opacity(0.25) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(item.label)
            }

            Divider().frame(height: 18)

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 38)
                .help("Color")

            Slider(value: $lineWidth, in: 1...24)
                .frame(width: 80)
                .help("Stroke width")

            Divider().frame(height: 18)

            Button { onRotate(90) } label: { Image(systemName: "rotate.left") }
                .buttonStyle(.plain).help("Rotate counter-clockwise")
            Button { onRotate(-90) } label: { Image(systemName: "rotate.right") }
                .buttonStyle(.plain).help("Rotate clockwise")
            Button { onFlip(true) } label: { Image(systemName: "arrow.left.and.right") }
                .buttonStyle(.plain).help("Flip horizontally")
            Button { onFlip(false) } label: { Image(systemName: "arrow.up.and.down") }
                .buttonStyle(.plain).help("Flip vertically")
            Button { onResize() } label: { Image(systemName: "aspectratio") }
                .buttonStyle(.plain).help("Resize…")

            Spacer()

            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain)
                .disabled(!document.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")

            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.plain)
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Rewrite the image pane around the toolbar**

Replace `Clipwise/Views/Editor/ImageEditorPane.swift` entirely:

```swift
import SwiftUI

struct ImageEditorPane: View {
    @Bindable var session: EditorSession

    @State private var tool: EditorTool = .pen
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var cropRect: CGRect?
    @State private var pendingTextOrigin: CGPoint?
    @State private var pendingText: String = ""
    @State private var isResizing = false
    @State private var resizeWidth: String = ""
    @State private var resizeHeight: String = ""

    var body: some View {
        if let document = session.document {
            VStack(spacing: 0) {
                EditorToolbarView(
                    tool: $tool,
                    color: $color,
                    lineWidth: $lineWidth,
                    document: document,
                    onRotate: { degrees in
                        cropRect = nil
                        document.applyTransform { ImageTransformService.rotate($0, degrees: degrees) }
                    },
                    onFlip: { horizontal in
                        cropRect = nil
                        document.applyTransform { ImageTransformService.flip($0, horizontal: horizontal) }
                    },
                    onResize: {
                        resizeWidth = String(Int(document.pixelSize.width))
                        resizeHeight = String(Int(document.pixelSize.height))
                        isResizing = true
                    }
                )

                Divider()

                ImageCanvasView(
                    document: document,
                    tool: tool,
                    color: color,
                    lineWidth: lineWidth,
                    cropRect: $cropRect,
                    pendingTextOrigin: $pendingTextOrigin,
                    pendingText: $pendingText,
                    onCommitText: { commitText(to: document) }
                )
                .padding(12)
                .background(Color(nsColor: .underPageBackgroundColor))

                if cropRect != nil {
                    cropBar(document: document)
                }

                if pendingTextOrigin != nil {
                    textBar(document: document)
                }
            }
            .sheet(isPresented: $isResizing) {
                resizeSheet(document: document)
            }
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bars

    private func cropBar(document: ImageEditorDocument) -> some View {
        HStack(spacing: 8) {
            Text("Drag to adjust the crop area.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                cropRect = nil
                tool = .pen
            }
            Button("Apply Crop") {
                if let rect = cropRect, rect.width >= 1, rect.height >= 1 {
                    document.applyTransform { ImageTransformService.crop($0, to: rect) }
                }
                cropRect = nil
                tool = .pen
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func textBar(document: ImageEditorDocument) -> some View {
        HStack(spacing: 8) {
            Text("Type the text, then press Return.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                pendingTextOrigin = nil
                pendingText = ""
            }
            Button("Add Text") { commitText(to: document) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func resizeSheet(document: ImageEditorDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resize Image").font(.headline)
            HStack(spacing: 8) {
                TextField("Width", text: $resizeWidth).frame(width: 80)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $resizeHeight).frame(width: 80)
                Text("px").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { isResizing = false }
                Button("Resize") {
                    if let width = Double(resizeWidth), let height = Double(resizeHeight),
                       width >= 1, height >= 1 {
                        document.applyTransform {
                            ImageTransformService.resize($0, to: CGSize(width: width, height: height))
                        }
                    }
                    isResizing = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Text placement

    private func commitText(to document: ImageEditorDocument) {
        defer {
            pendingTextOrigin = nil
            pendingText = ""
        }
        guard let origin = pendingTextOrigin,
              !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        document.add(ImageAnnotation(
            kind: .text(pendingText, origin: origin, fontSize: max(lineWidth * 5, 18)),
            color: color,
            lineWidth: lineWidth
        ))
    }
}
```

- [ ] **Step 3: Build, test, and run**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app
```

Expected: all tests still pass, build succeeds.

- [ ] **Step 4: Verify each tool manually**

Copy a screenshot and open its editor:

1. **Pen** — drag; change the colour and width, drag again; both strokes keep their own colour and width.
2. **Highlighter** — drag over dark text; the text stays readable through the translucent stroke.
3. **Arrow** — drag; the head sits at the release point and points along the drag.
4. **Rectangle / Ellipse** — drag in all four directions; the shape is always drawn correctly (no negative-size artifacts).
5. **Text** — click, type, press Return; the text lands where you clicked. Click, type, press Cancel; nothing is added.
6. **Redact** — drag over a region; it becomes pixelated, not black. (Black means `pixelatedBase` returned `nil` — check `ImageTransformService.pixelated`.)
7. **Crop** — drag a region, press Apply Crop; the image shrinks to that region and existing annotations are baked in. Undo restores both the size and the annotations.
8. **Rotate ↺ / ↻** — the image rotates the direction the icon suggests. If reversed, swap the two `onRotate` arguments in `ImageEditorPane`.
9. **Flip** — horizontal and vertical each mirror correctly.
10. **Resize** — enter half the width and height; the image shrinks and stays sharp.
11. **Cmd+Z / Cmd+Shift+Z** — step back and forward through every action above; buttons grey out at each end of the stack.
12. **Save** — reopen the item; the flattened result is what you saw on the canvas.

- [ ] **Step 5: Commit**

```bash
git add Clipwise/Views/Editor/EditorToolbarView.swift Clipwise/Views/Editor/ImageEditorPane.swift Clipwise.xcodeproj
git commit -m "feat: add image editor toolbar with all tools, transforms and undo"
```

---

### Task 10: Unsaved-changes guard and documentation

**Files:**
- Modify: `Clipwise/Views/Editor/EditorWindowController.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `EditorSession.hasUnsavedChanges`, `EditorSession.save(_:)` (Task 6); the `entries` map (Task 7).
- Produces: `EditorWindowController.windowShouldClose(_:)`.

- [ ] **Step 1: Add the guard**

In `Clipwise/Views/Editor/EditorWindowController.swift`, add this above `windowWillClose`:

```swift
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
```

A failed save returns `false` so the window stays open and the `EditorRootView` alert can show the reason.

- [ ] **Step 2: Build and run**

```bash
xcodegen generate
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -destination 'platform=macOS' test 2>&1 | tail -30
xcodebuild -project Clipwise.xcodeproj -scheme Clipwise -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/Clipwise-*/Build/Products/Debug/Clipwise.app
```

- [ ] **Step 3: Verify the guard**

1. Open a text item, type something, click the window's close button → the four-button alert appears.
2. **Cancel** → the window stays open with the edit intact.
3. **Discard** → the window closes and history is unchanged.
4. Repeat, choose **Save** → the window closes and the item is updated.
5. Repeat, choose **Save as Copy** → the window closes and a second row exists.
6. Open an item, change nothing, close → **no alert** (that would be a false positive on every open-and-look).
7. Press **Esc** with unsaved changes → same alert (Cancel routes through `performClose`).
8. Draw on an image, close → same alert appears for image edits.

- [ ] **Step 4: Full regression pass**

Run the complete manual checklist from the spec (§9):

1. Hover a text row → pencil appears; click it → panel hides, editor opens.
2. Click a row body → still pastes immediately.
3. `Cmd+E` on the selected row opens the editor.
4. Edit text → Save → panel shows updated title; pasting yields the new text.
5. Edit text → Save as Copy → both rows present.
6. Draw with each tool, resize the window → annotations stay locked to the image.
7. Redact a region → the saved PNG has that region pixelated.
8. Crop, rotate, flip, resize → undo restores the previous state.
9. Close with unsaved changes → alert appears and each button behaves.
10. Edit an item whose original had RTF (copy from Pages or a rich-text editor) → the warning banner shows, and after saving, pasting back into Pages yields the **new** text rather than the pre-edit content.

- [ ] **Step 5: Document the feature in `CLAUDE.md`**

Add this section after the existing `### Preview Popover` section:

```markdown
### Item Editor

Clipboard items with `primaryType == .text` or `.image` can be edited. Entry
points: a pencil button that appears on row hover/selection, a context-menu
`Edit` entry, and `Cmd+E` on the selected row. All three go through
`AppState.editItem(at:)` → `AppState.onOpenEditor` → `EditorWindowController`.

The editor opens in its own resizable `NSWindow`, not in the panel —
`FloatingPanel` dismisses itself on `resignKey`, so `AppDelegate` hides the panel
and opens the window 0.15s later, the same sequence used for Settings.

`EditorSession` is the shared state between the views and the window; the window
reads `hasUnsavedChanges` in `windowShouldClose` to decide whether to prompt.

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
content into Pages or Word. The editor shows a warning banner when this applies.
```

- [ ] **Step 6: Commit**

```bash
git add Clipwise/Views/Editor/EditorWindowController.swift CLAUDE.md Clipwise.xcodeproj
git commit -m "feat: guard editor close on unsaved changes and document the editor"
```

---

## Plan Self-Review

**Spec coverage:**

| Spec section | Task |
| --- | --- |
| §2 Entry points (hover, context menu, Cmd+E, `isEditable`) | 1, 7 |
| §3 Editor window, open sequence | 7 |
| §3 Unsaved-changes guard | 10 |
| §4 Text editor, RTF warning, plain-text-only save | 2, 6 |
| §5.1 Tool set | 4, 8, 9 |
| §5.2 Annotation model, pixel space, `pixelSize` from bitmap rep | 2, 4 |
| §5.3 Document, undo/redo cap 30 | 5 |
| §5.4 Shared `draw`, `ImageRenderer` flatten, redact cache | 4, 5 |
| §5.5 Transforms via CGContext, flatten-first | 3, 5 |
| §6 Save / Save as Copy, keyboard equivalents, PNG+TIFF, 10MB cap | 2, 6 |
| §7 Persistence, individual content deletes, hash overload | 1, 2 |
| §8 File layout | all |
| §9 Test target, unit tests, manual checklist | 1, 10 |

No gaps.

**Known deviations from the spec, all deliberate:**

- The spec's `EditorRootView(item:editService:onFinished:)` became
  `EditorRootView(session:onFinished:onCancel:)`. The window needs to read
  `hasUnsavedChanges`, which requires the session to be constructed by the
  controller rather than inside the view.
- `AnnotationRenderer.flatten` takes explicit parameters instead of an
  `ImageEditorDocument`, so it can be unit-tested without building a document —
  which is what lets the redact test pin the coordinate convention.
- Text placement uses an inline `TextField` on the canvas plus a confirm bar,
  rather than commit-on-click-away only. Click-away is ambiguous when the next
  click is itself a tool action.

**Type consistency:** `EditorTool`, `ImageAnnotation.Kind`, `ImageEditorDocument`,
`EditorSession`, `ItemEditService.SaveMode`, `Constants.maxContentSize`, and the
`ImageCanvasView` static helpers are spelled identically everywhere they appear
across Tasks 1–10.

**Highest-risk steps, and what to do:**

1. **Task 4, `ImageRenderer.cgImage`** — if it returns blank or mis-scaled output,
   replace only `flatten`'s body with a `CGContext` renderer. Never duplicate
   `draw`.
2. **Task 3, rotation direction** — the test pins one direction; if it fails on
   the quadrant assertion (not dimensions), flip the sign and the expectation
   together.
3. **Task 1, tests booting the app** — if tests hang or the status item appears
   during a run, the `XCTestCase` guard in `applicationDidFinishLaunching` is
   missing or placed after `appState = AppState()`.
