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
                        runTransform(document, failureMessage: "Could not rotate the image.") {
                            ImageTransformService.rotate($0, degrees: degrees)
                        }
                    },
                    onFlip: { horizontal in
                        runTransform(document, failureMessage: "Could not flip the image.") {
                            ImageTransformService.flip($0, horizontal: horizontal)
                        }
                    },
                    onResize: {
                        resizeWidth = String(Int(document.pixelSize.width))
                        resizeHeight = String(Int(document.pixelSize.height))
                        isResizing = true
                    },
                    onUndo: {
                        clearTransientToolState()
                        document.undo()
                    },
                    onRedo: {
                        clearTransientToolState()
                        document.redo()
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
            .onChange(of: tool) { _, _ in clearTransientToolState() }
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Transient tool state

    /// Clears state tied to the *current* pixel geometry: a crop marquee and
    /// a pending text caret are both stored as image-pixel coordinates, so
    /// anything that can change that geometry — rotate, flip, resize, undo,
    /// redo — or that switches away from the tool that owns them, must
    /// discard them first. Otherwise the crop bar (or text field) stays on
    /// screen pointing at coordinates that belong to an image that no longer
    /// exists: e.g. drag a crop selection, halve the image via Resize, then
    /// press Apply Crop — the rect is still in pre-resize pixel space, and
    /// either lands on the wrong region or fails and is silently discarded.
    ///
    /// One helper, called from every one of those places, rather than a
    /// separate ad hoc clear at each call site — that's what guarantees undo
    /// and redo (which don't go through `onRotate`/`onFlip`/`onResize`) don't
    /// get missed the way they were before.
    private func clearTransientToolState() {
        cropRect = nil
        pendingTextOrigin = nil
        pendingText = ""
    }

    /// Runs a geometry-changing transform: clears transient tool state tied
    /// to the pre-transform geometry, then applies `transform` via
    /// `ImageEditorDocument.applyTransform`. Surfaces a failure through
    /// `session.errorMessage` — the same alert channel `EditorRootView`
    /// already shows for save failures — instead of leaving the toolbar
    /// button appear to do nothing.
    private func runTransform(
        _ document: ImageEditorDocument,
        failureMessage: String,
        _ transform: (NSImage) -> NSImage?
    ) {
        clearTransientToolState()
        if !document.applyTransform(transform) {
            session.errorMessage = failureMessage
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
                    runTransform(document, failureMessage: "Could not crop the image.") {
                        ImageTransformService.crop($0, to: rect)
                    }
                } else {
                    cropRect = nil
                }
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

    /// Whether `resizeWidth`/`resizeHeight` currently parse to a size
    /// `ImageTransformService.resize` would actually accept: finite,
    /// `>= 1`, and at or under `maxDimension`. Drives both the Resize
    /// button's `disabled` state and whether Return in a text field submits
    /// — so garbage text, a negative, zero, an infinity, or an absurd
    /// fat-fingered value (e.g. "50000") are all visibly rejected rather
    /// than silently doing nothing when the sheet closes.
    private var resizeInputIsValid: Bool {
        guard let width = Double(resizeWidth), let height = Double(resizeHeight) else { return false }
        return width.isFinite && height.isFinite &&
            width >= 1 && height >= 1 &&
            width <= ImageTransformService.maxDimension &&
            height <= ImageTransformService.maxDimension
    }

    private func resizeSheet(document: ImageEditorDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resize Image").font(.headline)
            HStack(spacing: 8) {
                TextField("Width", text: $resizeWidth)
                    .frame(width: 80)
                    .onSubmit { performResize(document: document) }
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $resizeHeight)
                    .frame(width: 80)
                    .onSubmit { performResize(document: document) }
                Text("px").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { isResizing = false }
                    .keyboardShortcut(.cancelAction)
                Button("Resize") { performResize(document: document) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!resizeInputIsValid)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    /// Applies the resize sheet's current input, if valid, and closes the
    /// sheet. If the input isn't valid the sheet stays open and nothing
    /// happens — the Resize button is disabled for the same condition, so
    /// this only matters for a Return keypress in one of the text fields.
    private func performResize(document: ImageEditorDocument) {
        guard resizeInputIsValid,
              let width = Double(resizeWidth), let height = Double(resizeHeight)
        else { return }

        runTransform(document, failureMessage: "Could not resize the image.") {
            ImageTransformService.resize($0, to: CGSize(width: width, height: height))
        }
        isResizing = false
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
