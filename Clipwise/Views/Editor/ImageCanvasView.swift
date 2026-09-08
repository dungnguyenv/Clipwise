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

    /// True when a drag's two endpoints coincide — i.e. it never moved.
    /// `DragGesture(minimumDistance: 0)` fires `onChanged` even for a plain
    /// click, at which point the start and current locations are identical.
    /// Shape, redact, and crop tools treat that as no gesture at all: nobody
    /// drags out a zero-size rectangle or arrow on purpose, and a stray click
    /// should neither commit an invisible annotation nor overwrite a crop
    /// selection the user already made. Pen and highlighter are exempt —
    /// a single tap legitimately leaves a dot.
    static func isDegenerateDrag(_ a: CGPoint, _ b: CGPoint) -> Bool {
        a == b
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
                    guard !Self.isDegenerateDrag(origin, point) else { draft = nil; return }
                    draft = ImageAnnotation(
                        kind: .arrow(from: origin, to: point),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .rectangle:
                    guard !Self.isDegenerateDrag(origin, point) else { draft = nil; return }
                    draft = ImageAnnotation(
                        kind: .rectangle(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .ellipse:
                    guard !Self.isDegenerateDrag(origin, point) else { draft = nil; return }
                    draft = ImageAnnotation(
                        kind: .ellipse(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .redact:
                    guard !Self.isDegenerateDrag(origin, point) else { draft = nil; return }
                    draft = ImageAnnotation(
                        kind: .redact(Self.rect(origin, point)),
                        color: color,
                        lineWidth: lineWidth
                    )

                case .crop:
                    guard !Self.isDegenerateDrag(origin, point) else { return }
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
        // The first `onChanged` call of a drag reports the same point for both
        // start and current location — don't store that leading point twice.
        let initialPoints = origin == point ? [origin] : [origin, point]
        draft = ImageAnnotation(
            kind: .stroke(points: initialPoints, highlight: isHighlighter),
            color: color,
            // A highlighter only reads as one if it is fat.
            lineWidth: isHighlighter ? lineWidth * 3 : lineWidth
        )
    }
}
