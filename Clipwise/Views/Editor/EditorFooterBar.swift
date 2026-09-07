import SwiftUI

struct EditorFooterBar: View {
    @Bindable var session: EditorSession
    var onFinished: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if session.mode == .text {
                Text("\(session.text.count) characters · \(lineCount) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Save as Copy") {
                if session.save(.copy) { onFinished() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save") {
                if session.save(.overwrite) { onFinished() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var lineCount: Int {
        max(1, session.text.components(separatedBy: .newlines).count)
    }
}
