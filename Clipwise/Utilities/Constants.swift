import Foundation

enum Constants {
    static let historyLimitKey = "historyLimit"
    static let defaultHistoryLimit = 30
    static let ignoredAppsKey = "ignoredApps"
    static let searchModeKey = "searchMode"
    static let showDockIconKey = "showDockIcon"
    static let playSoundOnPasteKey = "playSoundOnPaste"
    static let hidePasswordsKey = "hidePasswords"
    static let popupWidthKey = "popupWidth"
    static let popupHeightKey = "popupHeight"

    static let defaultPopupWidth: CGFloat = 340
    static let defaultPopupHeight: CGFloat = 480
    static let maxTitleLength = 200
    static let thumbnailSize: CGFloat = 40
    static let pollingInterval: TimeInterval = 0.5

    /// Max stored bytes per pasteboard representation (10MB).
    static let maxContentSize = 10_000_000

    static let editorWindowWidth: CGFloat = 720
    static let editorWindowHeight: CGFloat = 560
    static let editorMinWidth: CGFloat = 520
    static let editorMinHeight: CGFloat = 420
}
