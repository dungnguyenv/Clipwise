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
        // `NSBitmapImageRep.setColor` silently writes zeroed (transparent
        // black) bytes for a color that isn't tagged with the legacy device
        // color space it expects — which rules out both a grayscale-space
        // color like `.white`/`.black` *and*, surprisingly, the numerically
        // identical color `.usingColorSpace(.deviceRGB)` produces (that one
        // is tagged with the modern `NSColorSpace`-based device RGB, not the
        // legacy one). Re-deriving the color via the legacy
        // `NSColor(deviceRed:green:blue:alpha:)` initializer — the same one
        // `ImageTransformServiceTests.makeQuadrantImage` uses throughout —
        // is what `setColor` actually needs.
        let components = color.usingColorSpace(.deviceRGB) ?? color
        let deviceColor = NSColor(
            deviceRed: components.redComponent, green: components.greenComponent,
            blue: components.blueComponent, alpha: components.alphaComponent
        )
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(deviceColor, atX: x, y: y)
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
