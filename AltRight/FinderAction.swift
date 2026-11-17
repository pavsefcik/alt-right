import AppKit

/// Actions the Finder extension can ask the main app to perform.
enum FinderAction: String, CaseIterable {
    case copyPath = "copy-path"
    case pastePath = "paste-path"
    case goToFolder = "go-to-folder"
    case connectToServer = "connect-to-server"
    case openSettings = "open-settings"

    var url: URL? {
        URL(string: "\(AppDelegate.urlScheme)://\(rawValue)")
    }
}
