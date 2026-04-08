import SwiftUI

struct IgnoredAppsView: View {
    @State private var ignoredApps: [String] = []
    @State private var newBundleID: String = ""

    var body: some View {
        Form {
            Section("Ignored Applications") {
                Text("Clipboard content from these apps will not be recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(ignoredApps.sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                ignoredApps.removeAll { $0 == bundleID }
                                saveApps()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 150)

                HStack {
                    TextField("Bundle ID (e.g. com.example.app)", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("Add") {
                        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !ignoredApps.contains(trimmed) else { return }
                        ignoredApps.append(trimmed)
                        newBundleID = ""
                        saveApps()
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("Reset to Defaults") {
                    ignoredApps = Array(AppFilterService.defaultIgnoredApps)
                    saveApps()
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if let saved = UserDefaults.standard.array(forKey: Constants.ignoredAppsKey) as? [String] {
                ignoredApps = saved
            } else {
                ignoredApps = Array(AppFilterService.defaultIgnoredApps)
            }
        }
    }

    private func saveApps() {
        UserDefaults.standard.set(ignoredApps, forKey: Constants.ignoredAppsKey)
    }
}
