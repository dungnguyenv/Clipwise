import AppKit
import Foundation

@MainActor
@Observable
final class AppFilterService {
    /// Default ignored bundle IDs (password managers)
    static let defaultIgnoredApps: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword8",
        "com.1password.1password",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.enpass.Enpass",
        "com.nordpass.NordPass",
    ]

    var ignoredBundleIDs: Set<String> {
        didSet {
            saveToDefaults()
        }
    }

    init() {
        if let saved = UserDefaults.standard.array(forKey: Constants.ignoredAppsKey) as? [String] {
            self.ignoredBundleIDs = Set(saved)
        } else {
            self.ignoredBundleIDs = Self.defaultIgnoredApps
            saveToDefaults()
        }
    }

    func isIgnored(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }

    func addIgnored(_ bundleID: String) {
        ignoredBundleIDs.insert(bundleID)
    }

    func removeIgnored(_ bundleID: String) {
        ignoredBundleIDs.remove(bundleID)
    }

    func resetToDefaults() {
        ignoredBundleIDs = Self.defaultIgnoredApps
    }

    private func saveToDefaults() {
        UserDefaults.standard.set(Array(ignoredBundleIDs), forKey: Constants.ignoredAppsKey)
    }
}
