import Foundation
import ServiceManagement

/// Wraps SMAppService so the login item status is always read from the system —
/// the user can remove the app from System Settings > Login Items at any time,
/// so a locally stored flag would go stale.
@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
