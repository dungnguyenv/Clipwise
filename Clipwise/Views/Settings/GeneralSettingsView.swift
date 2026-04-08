import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(Constants.historyLimitKey) private var historyLimit = Constants.defaultHistoryLimit
    @AppStorage(Constants.searchModeKey) private var searchMode = SearchMode.mixed.rawValue
    @AppStorage(Constants.playSoundOnPasteKey) private var playSoundOnPaste = false

    var body: some View {
        Form {
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
            }

            Section {
                Button("Clear All History") {
                    // Handled by AppState via environment
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
