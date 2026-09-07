import SwiftUI

struct ImageEditorPane: View {
    @Bindable var session: EditorSession

    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var cropRect: CGRect?
    @State private var pendingTextOrigin: CGPoint?
    @State private var pendingText: String = ""

    var body: some View {
        if let document = session.document {
            ImageCanvasView(
                document: document,
                tool: .pen,
                color: color,
                lineWidth: lineWidth,
                cropRect: $cropRect,
                pendingTextOrigin: $pendingTextOrigin,
                pendingText: $pendingText,
                onCommitText: {}
            )
            .padding(12)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
