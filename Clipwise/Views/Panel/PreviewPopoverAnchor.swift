import AppKit
import SwiftUI

/// Hosts the hover preview in an `NSPopover` whose behavior is `.applicationDefined`.
///
/// SwiftUI's `.popover` builds a `.transient` popover. A transient popover installs an
/// event monitor that closes it on the first mouse-down outside its bounds *and consumes
/// that event*. The preview follows the pointer, so a popover was open over whichever row
/// the mouse was on, and the first click on a row was always eaten dismissing it — the
/// pencil button and the row's own paste tap alike, both needing two clicks. The click
/// never reached SwiftUI at all, which is why nothing in the view layer could see it.
///
/// `.applicationDefined` installs no monitor, so clicks reach the row untouched and
/// visibility is driven entirely by `isPresented`. That is what this code already wanted:
/// the `.popover` this replaces passed a binding whose setter was a deliberate no-op, so
/// it was already refusing SwiftUI's dismissal requests — the transient monitor just ran
/// underneath it regardless.
///
/// The flip side of `.applicationDefined` is that nothing closes the popover for us, so
/// `isPresented` must go false whenever the preview should go away — including when the
/// panel hides, which does not clear `AppState.hoveredItemID` and whose `previewItem`
/// falls back to the selected row. See the call site in `ClipboardListView`.
struct PreviewPopoverAnchor: NSViewRepresentable {
    let isPresented: Bool
    let item: ClipboardItem

    func makeNSView(context: Context) -> NSView {
        PassthroughView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(isPresented: isPresented, item: item, anchor: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    /// Takes no part in hit testing. This view is an overlay covering the whole row purely
    /// so the popover can anchor to the row's rect the way `.popover` did; every click has
    /// to fall through to the row beneath it. `allowsHitTesting(false)` at the call site
    /// covers the SwiftUI side, this covers the AppKit side.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var popover: NSPopover?
        private var hosting: NSHostingController<AnyView>?

        func sync(isPresented: Bool, item: ClipboardItem, anchor: NSView) {
            // `anchor.window == nil` while a LazyVStack row is offscreen or being
            // recycled; showing a popover from a windowless view throws.
            guard isPresented, anchor.window != nil else {
                close()
                return
            }

            let content = AnyView(PreviewPopoverView(item: item).frame(width: 300))

            // Hovering across rows fires in quick succession. Swapping the root view of a
            // popover that is already up keeps it in place instead of tearing down and
            // rebuilding a window per row.
            if let popover, popover.isShown {
                hosting?.rootView = content
                return
            }

            close()

            let hosting = NSHostingController(rootView: content)
            let popover = NSPopover()
            popover.contentViewController = hosting
            popover.behavior = .applicationDefined
            // The preview tracks the pointer; the fade would lag behind it.
            popover.animates = false
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)

            self.hosting = hosting
            self.popover = popover
        }

        func close() {
            popover?.close()
            popover = nil
            hosting = nil
        }
    }
}
