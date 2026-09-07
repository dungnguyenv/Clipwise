import SwiftUI

struct SearchFieldView: View {
    @Binding var query: String
    var onQueryChanged: () -> Void
    var onEscape: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onReturn: () -> Void
    var onEdit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search clipboard...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .onChange(of: query) { _, _ in
                    onQueryChanged()
                }
                .onKeyPress(.downArrow) {
                    onArrowDown()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onArrowUp()
                    return .handled
                }
                .onKeyPress(.return) {
                    onReturn()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          press.characters.lowercased() == "e"
                    else { return .ignored }
                    onEdit()
                    return .handled
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    onQueryChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            isFocused = true
        }
    }
}
