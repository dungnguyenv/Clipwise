import SwiftUI

struct EditorRootView: View {
    @Bindable var session: EditorSession
    /// Called after a successful save — the window closes unconditionally.
    var onFinished: () -> Void
    /// Called for Cancel/Esc — routed through the window so the unsaved-changes
    /// guard runs.
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch session.mode {
            case .text:
                TextEditorPane(session: session)
            case .image:
                ImageEditorPane(session: session)
            }

            Divider()

            EditorFooterBar(session: session, onFinished: onFinished, onCancel: onCancel)
        }
        .frame(minWidth: Constants.editorMinWidth, minHeight: Constants.editorMinHeight)
        .alert(
            "Cannot Save",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            ),
            actions: {
                Button("OK") { session.errorMessage = nil }
            },
            message: {
                Text(session.errorMessage ?? "")
            }
        )
    }
}
