import SwiftUI

struct HotKeySettingsView: View {
    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack {
                    Text("Toggle Clipwise:")
                    Spacer()
                    Text("⌘⇧C")
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }

                Text("To customize the shortcut, the KeyboardShortcuts package can be integrated for a recorder UI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Navigation") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("↑ / ↓", "Navigate items")
                    shortcutRow("⏎ Return", "Paste selected item")
                    shortcutRow("⎋ Escape", "Close popup")
                    shortcutRow("⌘P", "Pin / Unpin item")
                    shortcutRow("⌫ Delete", "Remove item")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 100, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
