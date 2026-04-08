import AppKit

final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Constants.defaultPopupWidth,
                height: Constants.defaultPopupHeight
            ),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isFloatingPanel = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = true
        self.animationBehavior = .utilityWindow
        self.collectionBehavior = [.auxiliary, .moveToActiveSpace, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        // Hide traffic light buttons
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }

    /// Prevents double-firing of dismiss logic
    private var isDismissing = false

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        orderOut(nil)
        onDismiss?()
        isDismissing = false
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func showNearStatusItem(_ statusItem: NSStatusItem) {
        guard let buttonWindow = statusItem.button?.window else {
            center()
            makeKeyAndOrderFront(nil)
            return
        }

        let buttonFrame = buttonWindow.frame
        let panelWidth = frame.width
        let panelHeight = frame.height

        let x = buttonFrame.origin.x + buttonFrame.width / 2 - panelWidth / 2
        let y = buttonFrame.origin.y - panelHeight - 4

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }

    func showNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let panelWidth = frame.width
        let panelHeight = frame.height

        // Find the screen containing the cursor
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else {
            center()
            makeKeyAndOrderFront(nil)
            return
        }

        // Position: below-right of cursor with small offset
        var x = mouseLocation.x + 8
        var y = mouseLocation.y - panelHeight - 8

        // Clamp to screen bounds
        if x + panelWidth > visibleFrame.maxX {
            x = mouseLocation.x - panelWidth - 8
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        if y < visibleFrame.minY {
            y = mouseLocation.y + 8
        }
        if y + panelHeight > visibleFrame.maxY {
            y = visibleFrame.maxY - panelHeight
        }

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }
}
