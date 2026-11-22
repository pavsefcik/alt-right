import Foundation

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var lastError: String?

    let fileURL: URL

    private var loadFailed = false

    init(fileURL: URL = BookmarkStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("Alt Right", isDirectory: true)
            .appendingPathComponent("bookmarks.json", isDirectory: false)
    }

    var dataFolderURL: URL {
        fileURL.deletingLastPathComponent()
    }

    func load() {
        do {
            bookmarks = try read()
            loadFailed = false
            lastError = nil
        } catch {
            bookmarks = []
            loadFailed = true
            lastError = "Could not read bookmarks at \(fileURL.path).\n\n\(error.localizedDescription)"
        }
    }

    func upsert(_ bookmark: Bookmark) throws -> Bool {
        var updated = bookmarks

        if let index = updated.firstIndex(where: { $0.path == bookmark.path }) {
            updated[index] = bookmark
            try save(updated)
            bookmarks = updated
            return true
        }

        // Newest first: the list is what `Search Bookmarks` shows, and the
        // thing you just added is the thing you are most likely to look for.
        // Existing entries keep their position (editing must not reorder).
        updated.insert(bookmark, at: 0)
        try save(updated)
        bookmarks = updated
        return false
    }

    /// Rewrites the entry stored at `originalPath` in place. Editing a bookmark
    /// and correcting its path must update that bookmark, not add a second one
    /// while the stale one stays behind.
    func replace(originalPath: String, with bookmark: Bookmark) throws {
        var updated = bookmarks

        if let index = updated.firstIndex(where: { $0.path == originalPath }) {
            updated[index] = bookmark
            try save(updated)
            bookmarks = updated
        } else {
            _ = try upsert(bookmark)
        }
    }

    func remove(paths: Set<String>) throws {
        guard !paths.isEmpty else { return }
        let updated = bookmarks.filter { !paths.contains($0.path) }
        try save(updated)
        bookmarks = updated
    }

    func hasPath(_ path: String) -> Bool {
        bookmarks.contains { $0.path == path }
    }

    /// Records a successful open, which is what the relevance ranking learns
    /// from. The array order stays untouched; ordering happens at display time
    /// in `BookmarkRanker`.
    func markOpened(path: String) {
        guard let index = bookmarks.firstIndex(where: { $0.path == path }) else {
            return
        }

        var updated = bookmarks
        updated[index].lastOpenedAt = Date()
        updated[index].openCount += 1

        do {
            try save(updated)
            bookmarks = updated
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setPinned(_ pinned: Bool, path: String) {
        guard let index = bookmarks.firstIndex(where: { $0.path == path }) else {
            return
        }

        var updated = bookmarks
        updated[index].pinned = pinned

        do {
            try save(updated)
            bookmarks = updated
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func read() throws -> [Bookmark] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        return try JSONDecoder().decode([Bookmark].self, from: data)
    }

    private func save(_ entries: [Bookmark]) throws {
        if loadFailed {
            throw StoreError.refusesToOverwrite
        }

        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

enum StoreError: LocalizedError {
    case refusesToOverwrite

    var errorDescription: String? {
        switch self {
        case .refusesToOverwrite:
            return "The bookmark file could not be read, so Alt Right will not overwrite it."
        }
    }
}
