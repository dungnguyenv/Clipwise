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
