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
