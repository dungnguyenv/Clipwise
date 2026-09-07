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
                rep.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: x, y: y)
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
