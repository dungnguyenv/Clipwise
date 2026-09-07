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
                       width.isFinite, height.isFinite, width >= 1, height >= 1 {
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
