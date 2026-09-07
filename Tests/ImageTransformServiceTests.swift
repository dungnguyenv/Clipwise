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
