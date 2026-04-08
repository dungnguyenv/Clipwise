import SwiftUI

struct ClipboardListView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(appState.filteredItems.enumerated()), id: \.element.id) { index, item in
                        let isPreviewTarget = appState.previewItem?.id == item.id

                        ClipboardRowView(
                            item: item,
                            isSelected: index == appState.selectedIndex,
                            isHovering: appState.hoveredItemID == item.id
                        )
                        .id(item.id)
                        .onHover { hovering in
                            appState.hoveredItemID = hovering ? item.id : nil
                        }
                        .onTapGesture {
                            appState.selectedIndex = index
                            appState.selectAndPaste()
                        }
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                appState.togglePin(at: index)
                            }
                            Button("Delete") {
                                appState.deleteItem(at: index)
                            }
                            Divider()
                            Button("Copy") {
                                appState.pasteService.writeToPasteboard(item)
                            }
                        }
                        .popover(
                            isPresented: Binding(
                                get: { isPreviewTarget },
                                set: { _ in }
                            ),
                            arrowEdge: .trailing
                        ) {
                            PreviewPopoverView(item: item)
                                .frame(width: 300)
                        }

                        if index < appState.filteredItems.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .onChange(of: appState.selectedIndex) { _, newIndex in
                guard newIndex < appState.filteredItems.count else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(appState.filteredItems[newIndex].id, anchor: .center)
                }
            }
        }
    }
}
