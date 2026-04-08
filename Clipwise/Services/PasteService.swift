import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class PasteService {

    func paste(_ item: ClipboardItem, to targetApp: NSRunningApplication?, dismissPanel: (() -> Void)?) {
        let success = writeToPasteboard(item)
        guard success else {
            NSLog("[Clipwise] writeToPasteboard failed")
            return
        }

        dismissPanel?()

        let bundleID = targetApp?.bundleIdentifier
        let pid = targetApp?.processIdentifier

        if let bundleID {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        targetApp?.activate()

        // Wait for target to be frontmost on background thread, then paste
        Task.detached(priority: .userInitiated) {
            await Self.waitForFrontmost(pid: pid, timeout: 2.0)

            // Try osascript first, fall back to CGEvent
            if Self.simulateViaOsascript() {
                NSLog("[Clipwise] Paste via osascript OK")
            } else if AXIsProcessTrustedWithOptions(nil) {
                Self.simulateViaCGEvent()
                NSLog("[Clipwise] Paste via CGEvent")
            } else {
                NSLog("[Clipwise] FAILED: No paste method available. Requesting Accessibility...")
                await MainActor.run {
                    Self.promptAccessibility()
                }
            }
        }
    }

    @discardableResult
    func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let pbItem = NSPasteboardItem()
        pbItem.setData(Data(), forType: ClipboardMonitor.internalMarker)

        var typesWritten = 0
        for content in item.contents {
            guard let value = content.value, !value.isEmpty else { continue }
            let type = NSPasteboard.PasteboardType(content.type)
            pbItem.setData(value, forType: type)
            typesWritten += 1
        }

        NSLog("[Clipwise] Writing \(typesWritten) types to pasteboard")
        guard typesWritten > 0 else { return false }
        return pasteboard.writeObjects([pbItem])
    }

    // MARK: - Wait for target app

    private nonisolated static func waitForFrontmost(pid: pid_t?, timeout: TimeInterval) async {
        guard let pid else {
            try? await Task.sleep(for: .milliseconds(200))
            return
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let front = NSWorkspace.shared.frontmostApplication,
               front.processIdentifier == pid {
                try? await Task.sleep(for: .milliseconds(50))
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Method 1: osascript subprocess

    @discardableResult
    private nonisolated static func simulateViaOsascript() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"System Events\" to keystroke \"v\" using command down",
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return true
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? ""
            NSLog("[Clipwise] osascript error: \(errorStr)")
            return false
        } catch {
            NSLog("[Clipwise] osascript launch error: \(error)")
            return false
        }
    }

    // MARK: - Method 2: CGEvent

    private nonisolated static func simulateViaCGEvent() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Accessibility prompt

    private static func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Clipwise needs Accessibility permission to paste automatically.\n\nGo to: System Settings → Privacy & Security → Accessibility\n\nAdd and enable Clipwise."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
}
