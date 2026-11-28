import AppKit

@MainActor
final class BookmarkCoordinator {
    static let shared = BookmarkCoordinator()

    let bookmarks = BookmarkStore.shared
    let history = HistoryStore.shared
    let copyHistory = CopyHistoryStore.shared

    private init() {}

    /// The last path the user picked in Finder or copied anywhere.
    /// "Add Bookmark…" from the menu bar has no Finder context of its own, so it
    /// prefills this instead of guessing from the clipboard, which is usually
    /// text from somewhere else entirely.
    private static let lastPathKey = "lastPickedPath"

    private(set) var lastPickedPath: String? = UserDefaults.standard.string(forKey: BookmarkCoordinator.lastPathKey) {
        didSet { UserDefaults.standard.set(lastPickedPath, forKey: BookmarkCoordinator.lastPathKey) }
    }

    /// Remember the most recent path, for the next "Add Bookmark…".
    func rememberLastPath(_ paths: [String]) {
        guard let first = paths.compactMap(Bookmark.normalizedPath).first else { return }
        lastPickedPath = first
    }

    func start() {
        bookmarks.load()
        history.load()
        copyHistory.load()
    }

    func showSearch() {
        bookmarks.load()
        StatusItemController.shared.showPanelBookmarks()
    }

    func showHistory() {
        history.load()
        StatusItemController.shared.showPanelHistory()
    }

    func showCopyHistory() {
        copyHistory.load()
        StatusItemController.shared.showPanelCopyHistory()
    }

    func presentNewBookmark(
        initialPath: String = "",
        useFinderSelection: Bool = true,
        finderContext: NSRunningApplication? = nil,
        closeAfterSave: Bool = false
    ) {
        let path = initialPath.isEmpty
            ? preferredNewBookmarkPath(
                useFinderSelection: useFinderSelection,
                context: finderContext
            )
            : initialPath
        StatusItemController.shared.showPanelAddingBookmark(
            initialPath: path,
            closeAfterSave: closeAfterSave
        )
    }

    /// What a new bookmark should start with when the caller has no path of
    /// its own (the panel’s + Add button).
    ///
    /// Like the Finder context menu’s “Add as Bookmark”, this offers what is
    /// selected in Finder — or, when nothing is selected, the folder or server
    /// its front window is showing — but only when the user is actually
    /// working in Finder (see `finderLocation`). Otherwise the last path Alt
    /// Right saw and then the clipboard are used.
    func suggestedNewBookmarkPath() -> String {
        // The + Add button lives in a panel that is already open, so the app
        // the panel was opened from is the user's context.
        preferredNewBookmarkPath(
            useFinderSelection: true,
            context: StatusItemController.shared.applicationBeforePanel
        )
    }

    /// Finder’s selection and window location, but only when `context` really
    /// is Finder. A selection left behind in a Finder window hours ago is not
    /// what “Add Bookmark” should offer, so the caller passes the app the user
    /// came from.
    ///
    /// The result is non-nil for Finder even when there is no usable path:
    /// that lets the caller leave the field empty instead of injecting a path
    /// from a completely different folder. Querying Finder is an Apple event;
    /// it does not bring Finder forward, so it cannot dismiss the panel. It
    /// takes ~50 ms once warm.
    func finderLocation(when context: NSRunningApplication?) -> FinderSelection.Location? {
        guard context?.bundleIdentifier == "com.apple.finder" else { return nil }

        let started = Date()
        let location = FinderSelection.location()
        AppDelegate.log(
            String(
                format: "Finder location: %@ [%@] (%.0f ms); raw=%@",
                location.path ?? "<none>",
                location.source,
                Date().timeIntervalSince(started) * 1000,
                location.raw.isEmpty ? "<none>" : location.raw.joined(separator: " | ")
            )
        )
        return location
    }

    /// What the editor should start with when no path was handed over.
    ///
    /// The menu-bar item, the Add Bookmark hot key and the panel’s + Add all
    /// ask Finder what is selected right now, provided the user came from
    /// Finder; that is the folder or file they just chose. If Finder has no
    /// usable path (a server browser window, for example), the field stays
    /// empty rather than falling back to a path from an unrelated folder.
    /// Outside Finder the last path Alt Right saw and then the clipboard are
    /// used.
    private func preferredNewBookmarkPath(
        useFinderSelection: Bool,
        context: NSRunningApplication?
    ) -> String {
        // A caller that has its own context (the status-item menu) passes it;
        // otherwise the frontmost app is the context (the Add Bookmark hot key).
        let app = context ?? NSWorkspace.shared.frontmostApplication
        if useFinderSelection, let location = finderLocation(when: app) {
            if let path = location.path {
                rememberLastPath([path])
                return path
            }
            AppDelegate.log("Finder has no bookmarkable path here; leaving the field empty")
            return ""
        }
        return lastPickedPath ?? clipboardPath() ?? ""
    }

    func presentEditor(for bookmark: Bookmark) {
        StatusItemController.shared.showPanel(editing: bookmark)
    }

    func removeBookmark(path: String) {
        try? bookmarks.remove(paths: [path])
    }

    /// Opens a bookmark and records the use that drives relevance ranking.
    @discardableResult
    func open(
        _ bookmark: Bookmark,
        onEdit: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> Bool {
        let opened = BookmarkOpener.open(
            bookmark,
            onEdit: onEdit,
            onRemove: onRemove
        )
        if opened {
            bookmarks.markOpened(path: bookmark.path)
        }
        return opened
    }

    func recordHistory(paths: [String]) {
        rememberLastPath(paths)
        history.record(paths: paths)
    }

    /// The Finder extension sends Add Bookmark twice (notification + URL) so
    /// it works whether the app is running or has to be launched. Ignore the
    /// duplicate.
    private var lastAdd: (paths: [String], date: Date)?

    /// Handles paths sent from the Finder extension.
    func handleAdd(paths: [String]) {
        if let lastAdd,
           Date().timeIntervalSince(lastAdd.date) < 1.5,
           lastAdd.paths == paths {
            return
        }
        lastAdd = (paths, Date())

        let normalized = unique(paths.compactMap(Bookmark.normalizedPath))

        guard !normalized.isEmpty else {
            NSSound.beep()
            return
        }

        rememberLastPath(normalized)

        if normalized.count == 1, let path = normalized.first {
            // Finder asked for this form: saving goes back to Finder.
            presentNewBookmark(initialPath: path, closeAfterSave: true)
            return
        }

        confirmBatchAdd(paths: normalized)
    }

    private func confirmBatchAdd(paths: [String]) {
        let existingPaths = Set(bookmarks.bookmarks.map(\.path))
        let newPaths = paths.filter { !existingPaths.contains($0) }
        let skipped = paths.count - newPaths.count

        guard !newPaths.isEmpty else {
            AppActivation.activate()
            let alert = NSAlert()
            alert.messageText = L("Bookmarks Already Added")
            alert.informativeText = L("Every selected path is already a bookmark.")
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return
        }

        AppActivation.activate()

        let alert = NSAlert()
        alert.messageText = newPaths.count == 1
            ? String(format: L("Add %d bookmark?"), 1)
            : String(format: L("Add %d bookmarks?"), newPaths.count)
        alert.informativeText = skipped > 0
            ? (skipped == 1
                ? String(
                    format: L("%d path is already a bookmark and will be skipped."),
                    1
                )
                : String(
                    format: L("%d paths are already bookmarks and will be skipped."),
                    skipped
                ))
            : L("Titles will be created from each item’s file name.")
        alert.addButton(withTitle: L("Add"))
        alert.addButton(withTitle: L("Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var failures: [String] = []
        // Reversed: upsert puts each new bookmark on top, so walking the
        // selection backwards leaves the first selected item at the top.
        for path in newPaths.reversed() {
            let bookmark = Bookmark(
                path: path,
                title: Bookmark.automaticTitle(for: path)
            )
            do {
                _ = try bookmarks.upsert(bookmark)
            } catch {
                failures.append("\(path)\n\(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            let failureAlert = NSAlert()
            failureAlert.messageText = L("Some Bookmarks Could Not Be Added")
            failureAlert.informativeText = failures.joined(separator: "\n\n")
            failureAlert.addButton(withTitle: L("OK"))
            failureAlert.runModal()
        }

        showSearch()
    }

    private func clipboardPath() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return nil
        }

        let firstLine = raw.split(separator: "\n").first.map(String.init) ?? raw
        return Bookmark.normalizedPath(firstLine)
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

// MARK: - Pasteboard

/// Records what the clipboard holds: every text copy goes to the copy history,
/// and paths copied outside Alt Right — above all Finder's own ⌥⌘C (*Copy as
/// Pathname*), which the Finder Sync extension never sees because it is a
/// Finder command, not one of ours — also go to the path history.
///
/// There is no pasteboard-change notification, so this polls `changeCount` about
/// once a second (no disk, no network). Text marked concealed or transient by
/// the app that copied it (password managers do this) is never recorded.
@MainActor
final class PasteboardWatcher {
    static let shared = PasteboardWatcher()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxPaths = 200

    /// Marker types password managers and clipboard tools use to say "do not
    /// keep this": `org.nspasteboard.ConcealedType` for secrets and
    /// `org.nspasteboard.TransientType` for anything meant to be pasted once.
    private let skipTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
    ]

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount

        let timer = Timer(timeInterval: 0.7, repeats: true) { _ in
            Task { @MainActor in PasteboardWatcher.shared.poll() }
        }
        // .common, not .default: menus run in their own mode and a path copied
        // from a context menu must not be missed.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Marks whatever is on the clipboard right now as already seen, so the
    /// app's own Copy buttons do not re-record the entry they just wrote.
    func noteOwnWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string) else { return }

        let types = Set(pasteboard.types ?? [])
        guard types.isDisjoint(with: skipTypes) else { return }

        // Everything copied, text or paths: the copy history is the general one.
        CopyHistoryStore.shared.record(text: text)

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty, lines.count <= maxPaths else { return }

        let normalized = lines.compactMap(Bookmark.normalizedPath)
        // Every line has to be a path: "hello world" or a snippet of code must
        // not end up in the copied-path history.
        guard normalized.count == lines.count else { return }

        BookmarkCoordinator.shared.recordHistory(paths: normalized)
    }
}

// MARK: - Finder selection

/// Reads the selection and the displayed folder of Finder’s front window. This
/// is what “Add Bookmark” prefills when it is invoked from the menu bar or its
/// hot key, so the item the user just clicked in Finder is the one that gets
/// saved.
///
/// Finder reports sidebar picks and unmounted network shares differently from
/// ordinary file selections, and one unreadable item used to throw away the
/// whole result. The script therefore records every candidate separately and
/// never lets one failure abort the rest.
@MainActor
enum FinderSelection {
    struct Items {
        var paths: [String] = []
        var urls: [String] = []
        var names: [String] = []

        var isEmpty: Bool { paths.isEmpty && urls.isEmpty && names.isEmpty }
    }

    struct Location {
        let selection: Items
        let target: Items
        let raw: [String]
        /// The path or URL the editor should start with, if there is one.
        let path: String?
        /// Where `path` came from, for the log.
        let source: String
    }

    static func location() -> Location {
        let source = """
        set output to {}
        tell application "Finder"
            -- Outside every try: an Automation denial must surface as an error
            -- instead of quietly looking like an empty selection.
            set finderName to name
            try
                set seen to 0
                repeat with anItem in (selection)
                    set seen to seen + 1
                    if seen > 8 then exit repeat
                    try
                        set end of output to "SP|" & (POSIX path of (anItem as alias))
                    end try
                    try
                        set end of output to "SU|" & (URL of anItem as text)
                    end try
                    try
                        set end of output to "SN|" & (name of anItem as text)
                    end try
                end repeat
            end try
            try
                set wTarget to target of front Finder window
                try
                    set end of output to "TP|" & (POSIX path of (wTarget as alias))
                end try
                try
                    set end of output to "TU|" & (URL of wTarget as text)
                end try
                try
                    set end of output to "TN|" & (name of wTarget as text)
                end try
            end try
        end tell
        return output
        """

        guard let script = NSAppleScript(source: source) else {
            return Location(selection: Items(), target: Items(), raw: [], path: nil, source: "script unavailable")
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            // -1743: Automation not allowed. -1728: no selection or window.
            // Neither is worth an alert; the editor stays empty.
            AppDelegate.log("Finder location unavailable: \(error)")
            return Location(selection: Items(), target: Items(), raw: [], path: nil, source: "unavailable")
        }

        var selection = Items()
        var target = Items()
        var raw: [String] = []

        if result.numberOfItems > 0 {
            for index in 1...result.numberOfItems {
                guard let line = result.atIndex(index)?.stringValue, line.count > 3 else { continue }
                raw.append(line)

                let tag = String(line.prefix(3))
                let value = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                switch tag {
                case "SP|": selection.paths.append(value)
                case "SU|": selection.urls.append(value)
                case "SN|": selection.names.append(value)
                case "TP|": target.paths.append(value)
                case "TU|": target.urls.append(value)
                case "TN|": target.names.append(value)
                default: break
                }
            }
        }

        let chosen = choose(selection: selection, target: target)
        return Location(
            selection: selection,
            target: target,
            raw: raw,
            path: chosen.path,
            source: chosen.source
        )
    }

    /// The selection is the truth. Only when it has nothing usable is the
    /// window’s own location used — which is what makes a folder picked in the
    /// sidebar and a server picked in the server list work.
    private static func choose(
        selection: Items,
        target: Items
    ) -> (path: String?, source: String) {
        let server = serverInfo(from: target)

        // 1. A normal selection. A missing `/Volumes/…` path inside a server
        //    window means the share is not mounted: keep it as a URL instead
        //    of a path that cannot be opened.
        for raw in selection.paths {
            guard let path = Bookmark.normalizedPath(raw) else { continue }
            if let server,
               path.hasPrefix("/Volumes/"),
               !FileManager.default.fileExists(atPath: path) {
                let name = URL(fileURLWithPath: path).lastPathComponent
                if let url = networkShareURL(scheme: server.scheme, host: server.host, name: name) {
                    return (url, "rebuilt from an unmounted /Volumes selection")
                }
            }
            return (path, "Finder selection")
        }

        // 2. Finder sometimes exposes a URL where it refuses a POSIX path.
        for raw in selection.urls {
            if let url = Bookmark.networkURL(raw) { return (url, "Finder selection URL") }
            if let path = Bookmark.normalizedPath(raw) { return (path, "Finder selection URL") }
        }

        // 3. A share selected in a server browser window: its name is the
        //    share, the window’s URL or title is the server.
        if let server, let name = selection.names.first,
           let url = networkShareURL(scheme: server.scheme, host: server.host, name: name) {
            return (url, "rebuilt share URL from the selection name")
        }

        // 4. Nothing selected: use the folder the front window is showing
        //    (a sidebar pick leaves the content selection empty).
        for raw in target.paths {
            guard let path = Bookmark.normalizedPath(raw) else { continue }
            if FileManager.default.fileExists(atPath: path) {
                return (path, "Finder window")
            }
        }

        // 5. The window itself is a network location.
        for raw in target.urls {
            if let url = Bookmark.networkURL(raw) { return (url, "Finder window URL") }
            if let path = Bookmark.normalizedPath(raw) { return (path, "Finder window URL") }
        }

        // 6. The displayed folder is on a volume that is not mounted right now.
        for raw in target.paths {
            if let path = Bookmark.normalizedPath(raw) { return (path, "Finder window") }
        }

        // 7. A server window with nothing selected: bookmark the server.
        if let server,
           let url = networkShareURL(scheme: server.scheme, host: server.host, name: nil) {
            return (url, "server from the Finder window")
        }

        return (nil, "none")
    }

    /// The server a Finder browser window points at. Its URL is authoritative;
    /// the window title is the fallback, but only when it is an IP address — a
    /// folder called `example.com` must not turn into an SMB bookmark.
    private static func serverInfo(from items: Items) -> (scheme: String, host: String)? {
        for raw in items.urls {
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  Bookmark.networkSchemes.contains(scheme),
                  let host = url.host,
                  !host.isEmpty else { continue }
            return (scheme, host)
        }

        for raw in items.names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isIPv4(name) { return ("smb", name) }
        }

        return nil
    }

    private static func networkShareURL(scheme: String, host: String, name: String?) -> String? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                components.path = "/" + trimmed
            }
        }
        return components.string
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  part.count <= 3,
                  part.allSatisfy({ $0.isNumber }),
                  let value = Int(part) else { return false }
            return value <= 255
        }
    }
}
