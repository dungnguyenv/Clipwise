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

    // MARK: - Orientation

    private enum Quadrant: String {
        case red, green, blue, yellow, other
    }

    /// 40x20, quadrants: TL red, TR green, BL blue, BR yellow. Mirrors
    /// `ImageTransformServiceTests.makeQuadrantImage` — if the export path
    /// ever flips the base image vertically, this is what would catch it,
    /// since every other fixture in this file is a solid colour.
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

    /// Pins the export path's orientation. Every other fixture in this file is
    /// a solid colour, so a vertical flip introduced in `flatten` (or in the
    /// `Canvas`/`ImageRenderer` plumbing it depends on) would pass every other
    /// test here while silently turning every saved annotated image upside
    /// down.
    func testFlattenPreservesBaseImageOrientation() throws {
        let base = makeQuadrantImage()
        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [], pixelSize: base.pixelSize
        ))

        XCTAssertEqual(output.pixelSize, CGSize(width: 40, height: 20))
        XCTAssertEqual(quadrant(of: output, x: 5, y: 5), .red, "top-left should stay red")
        XCTAssertEqual(quadrant(of: output, x: 35, y: 5), .green, "top-right should stay green")
        XCTAssertEqual(quadrant(of: output, x: 5, y: 15), .blue, "bottom-left should stay blue")
        XCTAssertEqual(quadrant(of: output, x: 35, y: 15), .yellow, "bottom-right should stay yellow")
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

    /// Settles a question left open since Task 4's review: `drawStroke` sets
    /// `blendMode = .multiply` *inside* `drawLayer`, whose backdrop is a fresh,
    /// empty (fully transparent) image — not the base image already drawn in
    /// the outer context. Blending the stroke against nothing may make the
    /// multiply inert, silently reducing the highlighter to a plain
    /// 35%-alpha stroke.
    ///
    /// This is decidable without a GUI: multiply can never lighten a pixel —
    /// each output channel is at most `min(backdrop, source)` — whereas a
    /// plain alpha blend of a light colour over a dark background does
    /// lighten it (a 35%-opacity yellow over near-black is well above the
    /// background's brightness). So flatten a highlighter stroke over a dark
    /// region and check whether the result got brighter.
    func testHighlighterStrokeDoesNotLightenADarkBackground() throws {
        let backgroundColor = NSColor(deviceRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        let base = makeSolidImage(width: 40, height: 20, color: backgroundColor)
        let highlighterColor = NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1)
        let stroke = ImageAnnotation(
            kind: .stroke(points: [CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 10)], highlight: true),
            color: Color(nsColor: highlighterColor),
            lineWidth: 10
        )

        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [stroke], pixelSize: base.pixelSize
        ))

        let backgroundBrightness = try XCTUnwrap(brightness(of: base, x: 20, y: 1))
        let onStrokeBrightness = try XCTUnwrap(brightness(of: output, x: 20, y: 10))

        XCTAssertLessThanOrEqual(
            onStrokeBrightness, backgroundBrightness + 0.02,
            "a multiply blend can only darken or preserve a dark background — " +
                "if this fails, the highlighter's multiply blend mode is inert and it is " +
                "rendering as a plain translucent stroke instead"
        )

        // The assertion above is one-sided: a regression that dropped the
        // highlighter stroke entirely (drew nothing) would also leave the
        // pixel no brighter than the background, and would pass it right
        // along with a correctly-multiplied stroke. Pin the other half too —
        // the highlighter's yellow has a near-zero blue component, so a live
        // multiply must measurably darken the background's blue channel
        // specifically; an unchanged blue channel means nothing was drawn.
        let backgroundRep = try XCTUnwrap(base.bitmapRep)
        let backgroundColorAtPoint = try XCTUnwrap(
            backgroundRep.colorAt(x: 20, y: 1)?.usingColorSpace(.deviceRGB)
        )
        let outputRep = try XCTUnwrap(output.bitmapRep)
        let strokeColorAtPoint = try XCTUnwrap(
            outputRep.colorAt(x: 20, y: 10)?.usingColorSpace(.deviceRGB)
        )
        XCTAssertLessThan(
            strokeColorAtPoint.blueComponent, backgroundColorAtPoint.blueComponent - 0.01,
            "multiplying the background's blue channel by the highlighter's near-zero blue " +
                "component should measurably darken it — an unchanged blue channel means the " +
                "stroke was never drawn at all, not that it blended correctly"
        )
    }

    /// A single click (one point) takes a different code path in
    /// `drawStroke` than a drag (a fill, not a stroke) — pins that the dot
    /// still shares the highlighter's blend scope, so a tap and a drag with
    /// the same tool behave the same way rather than only the drag
    /// multiplying against the backdrop.
    ///
    /// Needs the same *pair* of assertions as the stroke test above, not
    /// just the blue-channel one: the highlighter's red and green components
    /// are both 1, so multiply leaves a dark backdrop's red/green channels
    /// unchanged while a plain alpha blend brightens them sharply — that's
    /// what actually distinguishes "multiplied" from "blended normally" here
    /// (and what the pre-fix dot, which used a plain `context.fill` outside
    /// any blend scope, would have failed). The blue channel alone would not
    /// have caught that regression: the highlighter's blue component is 0,
    /// so multiply and a plain alpha blend produce the same blue result —
    /// blue only distinguishes "something was drawn" from "nothing was".
    func testHighlighterDotDoesNotLightenADarkBackground() throws {
        let backgroundColor = NSColor(deviceRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        let base = makeSolidImage(width: 40, height: 20, color: backgroundColor)
        let highlighterColor = NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1)
        let dot = ImageAnnotation(
            kind: .stroke(points: [CGPoint(x: 20, y: 10)], highlight: true),
            color: Color(nsColor: highlighterColor),
            lineWidth: 10
        )

        let output = try XCTUnwrap(AnnotationRenderer.flatten(
            baseImage: base, pixelatedBase: nil, annotations: [dot], pixelSize: base.pixelSize
        ))

        let backgroundBrightness = try XCTUnwrap(brightness(of: base, x: 20, y: 1))
        let onDotBrightness = try XCTUnwrap(brightness(of: output, x: 20, y: 10))
        XCTAssertLessThanOrEqual(
            onDotBrightness, backgroundBrightness + 0.02,
            "a single-click highlighter dot should multiply against the backdrop exactly like " +
                "a dragged stroke does, not fall back to a plain alpha-blended fill"
        )

        let backgroundRep = try XCTUnwrap(base.bitmapRep)
        let backgroundColorAtPoint = try XCTUnwrap(
            backgroundRep.colorAt(x: 20, y: 1)?.usingColorSpace(.deviceRGB)
        )
        let outputRep = try XCTUnwrap(output.bitmapRep)
        let dotColorAtPoint = try XCTUnwrap(
            outputRep.colorAt(x: 20, y: 10)?.usingColorSpace(.deviceRGB)
        )
        XCTAssertLessThan(
            dotColorAtPoint.blueComponent, backgroundColorAtPoint.blueComponent - 0.01,
            "the dot should still be drawn at all, not omitted entirely"
        )
    }

    func testEditorToolCasesAllHaveIcons() {
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.systemImage.isEmpty, "\(tool.rawValue) needs an icon")
            XCTAssertFalse(tool.label.isEmpty, "\(tool.rawValue) needs a label")
        }
    }
}
