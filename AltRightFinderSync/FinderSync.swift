import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private enum Command: String {
        case pastePath = "paste-path"
    }

    override init() {
        super.init()

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
        item.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)

        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false

        addCopyPath(to: submenu)
        addPastePath(to: submenu)

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

    private func addPastePath(to menu: NSMenu) {
        let paste = NSMenuItem(
            title: L("Paste Path"),
            action: #selector(pastePath(_:)),
            keyEquivalent: ""
        )
        paste.target = self
        paste.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(paste)
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
    }

    @objc private func pastePath(_ sender: AnyObject?) {
        send(.pastePath)
    }

    private func send(_ command: Command) {
        guard let url = URL(string: "\(Self.appURLScheme)://\(command.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private static let appURLScheme = "altright"

    /// `path` on a directory URL keeps a trailing slash; Finder's ⌥⌘C does not.
    private static func displayPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
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
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
