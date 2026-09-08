import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(Constants.historyLimitKey) private var historyLimit = Constants.defaultHistoryLimit
    @AppStorage(Constants.searchModeKey) private var searchMode = SearchMode.mixed.rawValue
    @AppStorage(Constants.playSoundOnPasteKey) private var playSoundOnPaste = false
    @AppStorage(Constants.hidePasswordsKey) private var hidePasswords = true
    @State private var launchAtLogin = false
    /// The value we last handed to (or read from) the service. `.onChange` also
    /// observes our own rollback write, and this lets us tell that apart from a
    /// real user toggle without consulting the system status — which disagrees
    /// with the user's intent exactly when it matters (see the toggle handler).
    @State private var appliedLaunchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section("History") {
                HStack {
                    Text("History size:")
                    Spacer()
                    Picker("", selection: $historyLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("30").tag(30)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("300").tag(300)
                        Text("500").tag(500)
                        Text("700").tag(700)
                        Text("1000").tag(1000)
                    }
                    .frame(width: 100)
                }

                HStack {
                    Text("Search mode:")
                    Spacer()
                    Picker("", selection: $searchMode) {
                        ForEach(SearchMode.allCases, id: \.rawValue) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                    .frame(width: 100)
                }
            }

            Section("Behavior") {
                Toggle("Play sound on paste", isOn: $playSoundOnPaste)
                Toggle("Hide passwords & secrets", isOn: $hidePasswords)
            }

            Section {
                Button("Clear All History") {
                    // Handled by AppState via environment
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
            appliedLaunchAtLogin = launchAtLogin
        }
        .onChange(of: launchAtLogin) { _, newValue in
            // Comparing against the system status here would swallow a real
            // toggle whenever the two disagree: after register() lands in
            // .requiresApproval, isEnabled stays false while the switch reads
            // on, so switching it back off never reached unregister().
            guard newValue != appliedLaunchAtLogin else { return }
            do {
                try LaunchAtLoginService.setEnabled(newValue)
                appliedLaunchAtLogin = newValue
            } catch {
                appliedLaunchAtLogin = LaunchAtLoginService.isEnabled
                launchAtLogin = appliedLaunchAtLogin
            }
        }
    }
}
