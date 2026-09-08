import AppKit

final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?
    /// Fired for ⌘E. Handled here, not in `SearchFieldView`'s `TextField`, because the
    /// app installs no `NSMenu`/`.commands(...)` of its own — ⌘E is the default Edit
    /// menu's "Use Selection for Find" — and there is no reliable way from source to
    /// know whether a plain key-press handler in the field editor would ever see the
    /// event before menu key-equivalent dispatch claims it. Overriding
    /// `performKeyEquivalent` sidesteps the question: it wins whether AppKit consults
    /// the key window before the menu, or the menu item turns out to be disabled and
    /// the event falls through to us anyway.
    var onEdit: (() -> Void)?

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

    /// The four modifier keys that make a shortcut a different shortcut. Deliberately
    /// narrower than `.deviceIndependentFlagsMask`, which also includes `.capsLock`:
    /// intersecting against the full mask makes Caps Lock silently defeat the `==
    /// .command` match below (engaged, the intersection becomes `[.command,
    /// .capsLock]`), so ⌘E would stop working with no visible cause the moment a user
    /// has Caps Lock on.
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]

    /// Matches Command-E with no other *relevant* modifiers (see `relevantModifiers`),
    /// so ⌘⇧E / ⌘⌃E etc. pass through untouched, and Caps Lock doesn't matter either
    /// way. Returning `true` claims the event outright; returning `false` (via `super`)
    /// lets normal key-equivalent dispatch continue for everything else.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(Self.relevantModifiers) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onEdit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
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
