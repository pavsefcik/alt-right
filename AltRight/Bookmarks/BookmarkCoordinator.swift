import AppKit

@MainActor
final class BookmarkCoordinator {
    static let shared = BookmarkCoordinator()

    let bookmarks = BookmarkStore.shared
    let history = HistoryStore.shared

    private lazy var searchWindow = BookmarkSearchWindowController(store: bookmarks)
    private lazy var editorWindow = BookmarkEditorWindowController(store: bookmarks)
    private lazy var historyWindow = HistoryWindowController(store: history)

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
    }

    func showSearch() {
        bookmarks.load()
        searchWindow.show()
    }

    func showHistory() {
        history.load()
        historyWindow.show()
    }

    func presentNewBookmark(initialPath: String = "") {
        let path = initialPath.isEmpty
            ? (lastPickedPath ?? clipboardPath() ?? "")
            : initialPath
        editorWindow.present(existing: nil, initialPath: path)
    }

    func presentEditor(for bookmark: Bookmark) {
        editorWindow.present(existing: bookmark, initialPath: bookmark.path)
    }

    func removeBookmark(path: String) {
        try? bookmarks.remove(paths: [path])
    }

    func recordHistory(paths: [String]) {
        rememberLastPath(paths)
        history.record(paths: paths)
    }

    /// Handles paths sent from the Finder extension.
    func handleAdd(paths: [String]) {
        let normalized = unique(paths.compactMap(Bookmark.normalizedPath))

        guard !normalized.isEmpty else {
            NSSound.beep()
            return
        }

        rememberLastPath(normalized)

        if normalized.count == 1, let path = normalized.first {
            presentNewBookmark(initialPath: path)
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

/// Records paths copied outside Alt Right — above all Finder's own ⌥⌘C
/// (*Copy as Pathname*), which the Finder Sync extension never sees because it
/// is a Finder command, not one of ours.
///
/// There is no pasteboard-change notification, so this polls `changeCount` about
/// once a second (no disk, no network) and accepts the clipboard only when every
/// line is a path or URL `Bookmark.normalizedPath` understands. Copying prose,
/// code or a file itself is ignored.
@MainActor
final class PasteboardWatcher {
    static let shared = PasteboardWatcher()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxPaths = 200

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

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
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
