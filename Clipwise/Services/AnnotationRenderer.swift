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
