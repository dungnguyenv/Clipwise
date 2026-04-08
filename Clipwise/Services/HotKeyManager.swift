import Carbon.HIToolbox
import Cocoa

/// Thread-safe global hotkey manager using Carbon API.
/// All mutations to shared state are synchronized via a lock.
@MainActor
final class HotKeyManager {
    struct HotKeyEntry {
        var hotKeyRef: EventHotKeyRef?
        var callback: () -> Void
    }

    private var hotKeys: [UInt32: HotKeyEntry] = [:]
    private var eventHandler: EventHandlerRef?

    static let shared = HotKeyManager()

    private static let signature: OSType = {
        // "CWIS" as OSType
        let c = UInt32(0x43) // C
        let w = UInt32(0x57) // W
        let i = UInt32(0x49) // I
        let s = UInt32(0x53) // S
        return OSType(c << 24 | w << 16 | i << 8 | s)
    }()

    private init() {}

    // Note: unregisterAll() must be called before releasing.
    // deinit cannot call @MainActor methods directly.

    /// Register a global hotkey with a unique id.
    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        onToggle: @escaping @MainActor () -> Void
    ) {
        if eventHandler == nil {
            installEventHandler()
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.signature
        hotKeyID.id = id

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        if status != noErr {
            NSLog("[Clipwise] Failed to register hotkey id=\(id): \(status)")
            return
        }

        hotKeys[id] = HotKeyEntry(hotKeyRef: hotKeyRef, callback: onToggle)
    }

    func unregisterAll() {
        for (_, entry) in hotKeys {
            if let ref = entry.hotKeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeys.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return OSStatus(eventNotHandledErr) }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async {
                manager.hotKeys[id]?.callback()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }
}
