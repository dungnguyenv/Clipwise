import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(Constants.showDockIconKey) private var showDockIcon = true

    var body: some View {
        Form {
            Section("Dock") {
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }

                Text("When disabled, Clipwise will only appear in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Clipwise")
                        .font(.headline)
                    Spacer()
                    Text("v1.0.0")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Quit Clipwise") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
