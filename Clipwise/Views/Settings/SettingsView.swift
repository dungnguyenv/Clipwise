import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general
    case shortcuts
    case ignoredApps
    case appearance

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .ignoredApps: return "Ignored Apps"
        case .appearance: return "Appearance"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .shortcuts: return "keyboard"
        case .ignoredApps: return "eye.slash"
        case .appearance: return "paintbrush"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar-style tab bar
            HStack(spacing: 20) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .shortcuts:
                    HotKeySettingsView()
                case .ignoredApps:
                    IgnoredAppsView()
                case .appearance:
                    AppearanceSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 340)
    }
}

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(tab.title)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(width: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
