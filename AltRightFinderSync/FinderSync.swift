import Cocoa
import FinderSync

/// One mark for the whole app: an arrow pointing up and to the right.
let altRightIconName = "arrow.up.right"

final class FinderSync: FIFinderSync {
    private enum Command: String {
        case pastePath = "paste-path"
        case addBookmark = "add-bookmark"
        case recordHistory = "record-history"
    }

    override init() {
        super.init()

        ShortcutConfig.startObservingChanges()
        updateMonitoredDirectories()

        // Drives come and go while Finder is running (SMB shares, USB sticks, disk
        // images), and each one is its own root as far as Finder is concerned, so the
        // list has to be refreshed on every mount and unmount.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }

    @objc private func volumesChanged(_ notification: Notification) {
        updateMonitoredDirectories()
    }

    /// Finder only offers a Finder Sync extension's menu inside the folders it was told
    /// about. `/` is just the startup disk, so every mounted volume has to be listed
    /// separately — network shares such as `/Volumes/p-server` included.
    private func updateMonitoredDirectories() {
        var directories: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        directories.insert(FileManager.default.homeDirectoryForCurrentUser)

        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            directories.formUnion(volumes)
        }

        FIFinderSyncController.default().directoryURLs = directories

        NSLog("Alt Right: monitoring \(directories.map(\.path).sorted().joined(separator: ", "))")
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Finder inserts the returned menu's items directly into its context menu, so we
        // hand it a single "Alt Right" item that owns our submenu.
        let root = NSMenu(title: L("Alt Right"))
        root.autoenablesItems = false

        let title = L("Alt Right")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: altRightIconName, accessibilityDescription: nil)

        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false

        let shortcuts = ShortcutConfig.load()

        addCopyPath(to: submenu)
        addPastePath(to: submenu, shortcut: shortcuts.pastePath)
        submenu.addItem(.separator())
        addAddBookmark(to: submenu)

        item.submenu = submenu
        root.addItem(item)
        return root
    }

    private func addCopyPath(to menu: NSMenu) {
        let item = NSMenuItem(
            title: L("Copy Path"),
            action: #selector(copyPath(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(item)
    }

    private func addPastePath(to menu: NSMenu, shortcut: Shortcut) {
        let paste = NSMenuItem(
            title: L("Paste Path"),
            action: #selector(pastePath(_:)),
            keyEquivalent: shortcut.key.lowercased()
        )
        paste.target = self
        paste.keyEquivalentModifierMask = shortcut.eventModifiers
        paste.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(paste)
    }

    private func addAddBookmark(to menu: NSMenu) {
        let item = NSMenuItem(
            title: L("Add as Bookmark"),
            action: #selector(addBookmark(_:)),
            keyEquivalent: ""
        )
        item.target = self
        // "bookmark.badge.plus" does not exist as an SF Symbol, so this item
        // silently had no icon at all.
        item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil)
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func copyPath(_ sender: AnyObject?) {
        let urls = targets()
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }

        let paths = urls.map(Self.displayPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)

        if let data = Self.encodePaths(paths) {
            send(.recordHistory, data: data, activates: false)
        }
    }

    @objc private func pastePath(_ sender: AnyObject?) {
        send(.pastePath)
    }

    @objc private func addBookmark(_ sender: AnyObject?) {
        let paths = clickedTargets().map(Self.displayPath)
        guard !paths.isEmpty, let data = Self.encodePaths(paths) else {
            NSSound.beep()
            return
        }

        // The URL scheme is how a cold app launch receives the paths. When the
        // app is already running, the distributed notification gets there
        // instantly and does not depend on the Apple-event handler staying
        // installed (SwiftUI can take it over when a scene appears).
        DistributedNotificationCenter.default().postNotificationName(
            AddBookmarkNotification.name,
            object: nil,
            userInfo: ["data": data],
            deliverImmediately: true
        )
        send(.addBookmark, data: data)
    }

    private func send(_ command: Command, data: String? = nil, activates: Bool = true) {
        var components = URLComponents()
        components.scheme = Self.appURLScheme
        components.host = command.rawValue
        if let data {
            components.queryItems = [URLQueryItem(name: "data", value: data)]
        }

        guard let url = components.url else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.open(url, configuration: configuration, completionHandler: nil)
    }

    // MARK: - Helpers

    private static let appURLScheme = "altright"

    private static func encodePaths(_ paths: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(paths) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `path` on a directory URL keeps a trailing slash; Finder's ⌥⌘C does not.
    private static func displayPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// The item(s) the user acted on.
    ///
    /// Selection, not `targetedURL()`, is the truth for a right-click on an
    /// item: Finder selects the item before showing the menu. `targetedURL()`
    /// reports the enclosing folder for a file in some Finder versions, which
    /// made Add Bookmark save the folder above the clicked file. The target is
    /// only a fallback for a background/container right-click.
    private func clickedTargets() -> [URL] {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []

        if !selected.isEmpty { return selected }
        if let targeted = controller.targetedURL() { return [targeted] }
        return []
    }

    private func targets() -> [URL] {
        let controller = FIFinderSyncController.default()

        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let targeted = controller.targetedURL() {
            return [targeted]
        }
        return []
    }

    override var toolbarItemName: String { L("Alt Right") }
    override var toolbarItemToolTip: String { L("Alt Right actions") }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: altRightIconName, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
