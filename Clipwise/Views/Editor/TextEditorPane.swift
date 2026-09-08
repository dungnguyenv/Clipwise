import SwiftUI

struct TextEditorPane: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            if session.hasRichTextRepresentation {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Saving converts this item to plain text — its formatted version is discarded.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            TextEditor(text: $session.text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
    }
}
