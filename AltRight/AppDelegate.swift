import AppKit
import SwiftUI

/// The main app never shows a window at launch: it lives in the menu bar and acts as
/// the "muscle" for the Finder extension. Sandboxed app extensions may not post
/// keyboard events, so the extension asks us to do it through a URL scheme.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let urlScheme = "altright"

    /// SwiftUI owns the delegate instance, so keep a reference to it for the UI.
    private(set) static weak var shared: AppDelegate?

    override init() {
        super.init()
        Self.shared = self
    }

    static func log(_ message: String) {
        NSLog("Alt Right: \(message)")
    }

    func installURLEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI installs its own kAEGetURL handler while the scenes start up, which
        // would swallow our events, so claim the URL events again once it's done.
        installURLEventHandler()
        BookmarkCoordinator.shared.start()
        StatusModel.shared.start()
    }

    /// The app is an accessory (LSUIElement), so its settings window is created and
    /// shown by hand instead of by a SwiftUI scene.
    private lazy var settingsWindow: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Alt Right"
        window.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: ContentView())
        window.contentView = hosting
        let ideal = hosting.fittingSize
        window.setContentSize(NSSize(width: 480, height: max(ideal.height, 320)))
        window.center()
        window.setFrameAutosaveName("AltRightSettings")
        return window
    }()

    func showSettings() {
        Self.log("showSettings")
        AppActivation.activate()
        StatusModel.shared.refresh()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "<none>"
        guard
            let url = URL(string: raw),
            url.scheme == Self.urlScheme,
            let host = url.host
        else {
            Self.log("unhandled url \(raw)")
            return
        }

        if let command = BookmarkCommand(rawValue: host) {
            Self.log("handling bookmark url \(raw)")
            handleBookmarkCommand(command, url: url)
            return
        }

        guard let action = FinderAction(rawValue: host) else {
            Self.log("unhandled url \(raw)")
            return
        }

        Self.log("handling url \(raw)")
        FinderActuator.perform(action)
    }

    private func handleBookmarkCommand(_ command: BookmarkCommand, url: URL) {
        switch command {
        case .searchBookmarks:
            BookmarkCoordinator.shared.showSearch()

        case .recordHistory:
            if let paths = paths(from: url) {
                BookmarkCoordinator.shared.recordHistory(paths: paths)
            }

        case .addBookmark:
            guard let paths = paths(from: url) else {
                NSSound.beep()
                return
            }
            BookmarkCoordinator.shared.handleAdd(paths: paths)
        }
    }

    private func paths(from url: URL) -> [String]? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let paths = PathPayload.decode(value) else {
            return nil
        }
        return paths
    }
}

enum BookmarkCommand: String {
    case addBookmark = "add-bookmark"
    case searchBookmarks = "search-bookmarks"
    case recordHistory = "record-history"
}

enum AppActivation {
    /// Bring the (accessory) app forward without touching deprecated APIs.
    static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
