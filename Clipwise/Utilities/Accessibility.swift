import ApplicationServices
import Foundation

enum AccessibilityHelper {
    /// Check if the app has accessibility permission (needed for CGEvent paste simulation)
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permission
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
