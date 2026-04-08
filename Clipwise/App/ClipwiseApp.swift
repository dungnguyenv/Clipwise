import SwiftUI

@main
struct ClipwiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.appState ?? AppState())
        }
    }
}
