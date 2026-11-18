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
        let path = initialPath.isEmpty ? clipboardPath() ?? "" : initialPath
        editorWindow.present(existing: nil, initialPath: path)
    }

    func presentEditor(for bookmark: Bookmark) {
        editorWindow.present(existing: bookmark, initialPath: bookmark.path)
    }

    func removeBookmark(path: String) {
        try? bookmarks.remove(paths: [path])
    }

    func recordHistory(paths: [String]) {
        history.record(paths: paths)
    }

    /// Handles paths sent from the Finder extension.
    func handleAdd(paths: [String]) {
        let normalized = unique(paths.compactMap(Bookmark.normalizedPath))

        guard !normalized.isEmpty else {
            NSSound.beep()
            return
        }

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
        for path in newPaths {
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
