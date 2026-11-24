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
    private var spotlightTimer: Timer?
    /// Consecutive polls that reported Spotlight as active. One frame in the
    /// middle of the overlay's animation must not be enough to dismiss.
    private var spotlightConfirmations = 0

    override init() {
        super.init()
        Self.shared = self
    }

    static func log(_ message: String) {
        NSLog("Alt Right: \(message)")
        recordEvent("· \(message)")
    }

    /// Where “why did the panel close?” is recorded. Console.app does not
    /// reliably show an accessory app's NSLog output, so panel presentations
    /// and dismissals are appended to a small plain-text file:
    ///
    ///   ~/Library/Application Support/Alt Right/close-log.txt
    ///
    /// One line per event: ISO timestamp, then what happened. The file is
    /// trimmed to the last 200 lines so it cannot grow without bound.
    static func recordEvent(_ event: String) {
        let directory = BookmarkStore.defaultFileURL.deletingLastPathComponent()
        let file = directory.appendingPathComponent("close-log.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())

        var lines = (try? String(contentsOf: file, encoding: .utf8))?
            .split(separator: "\n")
            .map(String.init) ?? []
        lines.append("\(stamp)  \(event)")
        if lines.count > 200 {
            lines.removeFirst(lines.count - 200)
        }

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? (lines.joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
    }

    static func recordDismissal(_ reason: String) {
        NSLog("Alt Right: closePanel: \(reason)")
        recordEvent("closed: \(reason)")
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAddBookmarkNotification(_:)),
            name: AddBookmarkNotification.name,
            object: nil
        )
        BookmarkCoordinator.shared.start()
        ShortcutStore.shared.load()
        ShortcutConfig.startServingChanges()
        PasteboardWatcher.shared.start()
        StatusModel.shared.start()
        GlobalHotKeys.shared.start()
        StatusItemController.shared.install()

        startSpotlightWatch()
    }

    /// Spotlight in macOS 26 takes focus without deactivating or activating an
    /// app, so the only dependable signal is polling the focused AX element
    /// while Alt Right has a window on screen.
    private func startSpotlightWatch() {
        guard spotlightTimer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSpotlight() }
        }
        RunLoop.main.add(timer, forMode: .common)
        spotlightTimer = timer
    }

    /// Called whenever the panel is put on screen. The app can already be active
    /// (the panel is an accessory app's popover), so `applicationDidBecomeActive`
    /// does not necessarily fire.
    func ensureSpotlightWatch() {
        guard StatusItemController.shared.isPanelShown else { return }
        startSpotlightWatch()
    }

    private func stopSpotlightWatch() {
        spotlightTimer?.invalidate()
        spotlightTimer = nil
        spotlightConfirmations = 0
    }

    private func pollSpotlight() {
        // Only the panel needs this watch. The settings window can stay where
        // it is, and with nothing of ours on screen there is no reason to keep
        // touching the AX system.
        guard StatusItemController.shared.isPanelShown else {
            stopSpotlightWatch()
            return
        }

        // A file panel or an alert of ours owns the screen; Spotlight cannot be
        // in front of it, and closing under a modal would strand the user.
        guard NSApp.modalWindow == nil else {
            spotlightConfirmations = 0
            return
        }

        // Definitive: the overlay owns the keyboard. No need to wait.
        if SpotlightDetector.isActive() {
            spotlightConfirmations = 0
            closeForSpotlight()
            return
        }

        // Fallback without Accessibility permission: a fully drawn Spotlight
        // window. This one needs a second sample, because a window can be in
        // the middle of an animation.
        guard SpotlightDetector.windowIsVisible() else {
            spotlightConfirmations = 0
            return
        }
        spotlightConfirmations += 1
        guard spotlightConfirmations >= 2 else { return }
        spotlightConfirmations = 0
        closeForSpotlight()
    }

    func closeForSpotlight() {
        guard StatusItemController.shared.isPanelShown else { return }
        Self.log("Spotlight appeared; closing the panel")
        stopSpotlightWatch()
        // Close the panel only. Hiding the app (the old behaviour) deactivated
        // it while the Spotlight overlay was still animating in, and macOS 26
        // then dismissed Spotlight as well — both flickered and disappeared.
        StatusItemController.shared.closePanel(reason: "spotlight")
    }

    /// The app is an accessory (LSUIElement), so it cannot rely on a SwiftUI
    /// window scene being brought forward by a selector. The settings window is
    /// owned here, exactly like the menu-bar panel.
    private lazy var settingsWindow: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Alt Right"
        window.isReleasedWhenClosed = false
        // Open on the Desktop (Space) the user is on, not on the one the
        // window was last used in.
        window.collectionBehavior = [.moveToActiveSpace]

        let hosting = NSHostingView(rootView: ContentView())
        window.contentView = hosting
        let ideal = hosting.fittingSize
        window.setContentSize(NSSize(width: 480, height: max(ideal.height, 320)))
        window.setFrameAutosaveName("AltRightSettings")
        return window
    }()

    func showSettings() {
        Self.log("showSettings")
        StatusItemController.shared.closePanel(reason: "showSettings")
        AppActivation.activate()
        NSApp.activate(ignoringOtherApps: true)
        StatusModel.shared.refresh()
        Self.place(settingsWindow, on: Self.activeScreen())
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    /// The screen the user is working on: the one under the pointer, which is
    /// also the screen whose Space was active when the menu-bar item was
    /// clicked. Falls back to the main screen.
    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
    }

    /// Center a window on `screen` when it is not already there. The autosaved
    /// frame wins otherwise, so a window the user moved keeps its position.
    private static func place(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else { return }
        if let current = window.screen, current.frame.equalTo(screen.frame) {
            return
        }

        let visible = screen.visibleFrame
        let size = NSSize(
            width: min(window.frame.width, visible.width - 20),
            height: min(window.frame.height, visible.height - 20)
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// SwiftUI may replace the Apple-event handler when a scene appears (the
    /// Settings window, for example). Claim it again whenever we come forward.
    func applicationDidBecomeActive(_ notification: Notification) {
        installURLEventHandler()
        startSpotlightWatch()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Keep polling while the panel is still on screen: not every activation
        // change is a dismissal (Control Center and Notification Center take
        // focus for a moment), and Spotlight can still appear over the panel.
        guard !StatusItemController.shared.isPanelShown else { return }
        stopSpotlightWatch()
    }

    @objc private func handleAddBookmarkNotification(_ notification: Notification) {
        guard let value = notification.userInfo?["data"] as? String,
              let paths = PathPayload.decode(value) else {
            return
        }
        BookmarkCoordinator.shared.handleAdd(paths: paths)
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
            if let paths = paths(from: url) {
                BookmarkCoordinator.shared.rememberLastPath(paths)
            }
            BookmarkCoordinator.shared.showSearch()

        case .openHistory:
            if let paths = paths(from: url) {
                BookmarkCoordinator.shared.rememberLastPath(paths)
            }
            BookmarkCoordinator.shared.showHistory()

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
    case openHistory = "open-history"
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
