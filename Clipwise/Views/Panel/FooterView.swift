import SwiftUI

struct FooterView: View {
    let itemCount: Int
    var onClearAll: () -> Void

    var body: some View {
        HStack {
            Text("\(itemCount) items")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear All") {
                onClearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
