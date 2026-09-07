import SwiftUI

struct EditorFooterBar: View {
    @Bindable var session: EditorSession
    var onFinished: () -> Void
    var onCancel: () -> Void

    /// Above this many UTF-8 bytes, the character/line counter is skipped rather than
    /// recomputed on every keystroke. `session.text` can be as large as
    /// `Constants.maxContentSize` (~10 MB); counting characters and lines is O(n), and
    /// recomputing that on every render at that scale would visibly stutter typing.
    /// `utf8.count` is the cheap pre-check — a native Swift `String` tracks its UTF-8
    /// byte count directly, so reading it doesn't itself walk the string — used to decide
    /// whether the O(n) pass below is worth paying for.
    private static let statsByteLimit = 100_000

    var body: some View {
        HStack(spacing: 10) {
            if session.mode == .text, let stats {
                Text(stats)
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

    /// `nil` above `statsByteLimit` — the counter is omitted entirely rather than shown
    /// stale or computed expensively.
    private var stats: String? {
        let text = session.text
        guard text.utf8.count <= Self.statsByteLimit else { return nil }

        // Single pass over `Character`s, no intermediate array: unlike
        // `text.components(separatedBy: .newlines).count`, this allocates nothing.
        var characters = 0
        var newlines = 0
        for character in text {
            characters += 1
            if character.isNewline { newlines += 1 }
        }
        return "\(characters) characters · \(newlines + 1) lines"
    }
}
