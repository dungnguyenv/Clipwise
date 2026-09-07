import SwiftUI

struct PanelContentView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: Search + Settings
            HStack(spacing: 6) {
                SearchFieldView(
                    query: $appState.searchQuery,
                    onQueryChanged: { appState.applySearch() },
                    onEscape: onDismiss,
                    onArrowDown: { appState.moveSelection(by: 1) },
                    onArrowUp: { appState.moveSelection(by: -1) },
                    onReturn: {
                        appState.selectAndPaste()
                    }
                )

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .padding(.trailing, 10)
            }

            Divider()

            ClipboardListView(appState: appState, onDismiss: onDismiss)

            Divider()

            FooterView(
                itemCount: appState.filteredItems.count,
                onClearAll: { appState.clearAll() }
            )
        }
        .frame(
            width: Constants.defaultPopupWidth,
            height: Constants.defaultPopupHeight
        )
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
