import Combine
import Foundation

/// State for the menu-bar quick panel. It is the whole bookmark window for the
/// left-click surface: search, sort, ranked rows, actions, and the inline
/// add/edit form all live here. The full Bookmarks window keeps its own
/// multi-selection; this one is single-selection.
@MainActor
final class QuickPanelModel: ObservableObject {
    enum Mode: Equatable {
        case bookmarks
        case history
        case copyHistory
    }

    struct EditorRequest: Identifiable {
        let id = UUID()
        let bookmark: Bookmark?
        let initialPath: String
    }

    /// Typed into the search field. Filtering runs on every keystroke; at
    /// bookmark-list sizes the ranking is a few dozen microseconds.
    @Published var query = "" {
        didSet { refresh() }
    }

    @Published var sort: BookmarkSort = .relevance {
        didSet { refresh() }
    }

    /// Non-nil while the inline form replaces the list in this panel.
    @Published var editor: EditorRequest?

    /// Bookmarks or History — both faces share this window. The choice is
    /// remembered so the next launch opens on the face the user left behind.
    @Published private(set) var mode: Mode = QuickPanelModel.savedMode() {
        didSet {
            guard mode != oldValue else { return }
            let value: String
            switch mode {
            case .bookmarks: value = Self.bookmarksModeValue
            case .history: value = Self.historyModeValue
            case .copyHistory: value = Self.copyHistoryModeValue
            }
            UserDefaults.standard.set(value, forKey: Self.modeDefaultsKey)
        }
    }

    private static let modeDefaultsKey = "quickPanelMode"
    private static let bookmarksModeValue = "bookmarks"
    private static let historyModeValue = "history"
    private static let copyHistoryModeValue = "copy-history"

    static func savedMode() -> Mode {
        switch UserDefaults.standard.string(forKey: modeDefaultsKey) {
        case historyModeValue: return .history
        case copyHistoryModeValue: return .copyHistory
        default: return .bookmarks
        }
    }

    let history: HistoryPanelModel
    let copyHistory: CopyHistoryPanelModel

    @Published private(set) var results: [Bookmark] = []
    @Published private(set) var selectedID: Bookmark.ID?

    /// Requests that the list scroll a row into the middle. Only deliberate
    /// moves (arrow keys) post one: a mouse click selects the row but leaves
    /// it where it is, so the row does not slide away between the two clicks
    /// of a double click. The generation makes repeated requests for the same
    /// row observable.
    struct ScrollRequest: Equatable {
        let id: String
        let generation: Int
    }

    @Published private(set) var scrollRequest: ScrollRequest?
    private var scrollGeneration = 0

    /// Bumped every time the panel is summoned so the view can move focus into
    /// the field even though it stays alive between presentations.
    @Published private(set) var focusGeneration = 0

    private let store: BookmarkStore
    private var storeObserver: AnyCancellable?

    init(store: BookmarkStore, historyStore: HistoryStore, copyHistoryStore: CopyHistoryStore) {
        self.store = store
        self.history = HistoryPanelModel(store: historyStore)
        self.copyHistory = CopyHistoryPanelModel(store: copyHistoryStore)

        // Pin, delete and edit happen from this panel; keep the visible list in
        // step without waiting for the next keystroke.
        storeObserver = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var bookmarkStore: BookmarkStore { store }

    var selectedResult: Bookmark? {
        guard let selectedID else { return nil }
        return results.first { $0.id == selectedID }
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareForShow() {
        store.load()
        // Open on the face the panel was left on last time. The explicit
        // Bookmarks/History commands override this right afterwards.
        mode = Self.savedMode()
        editor = nil
        query = ""
        history.reset()
        copyHistory.reset()
        refresh()
        focusGeneration += 1
    }

    func showHistory() {
        show(.history)
    }

    func showBookmarks() {
        show(.bookmarks)
    }

    func showCopyHistory() {
        show(.copyHistory)
    }

    /// The one place that swaps the face of the panel. The ring order is the
    /// order of the arrow keys: Bookmarks → Paths → Copies → Bookmarks, with
    /// the left arrow walking the ring backwards.
    func show(_ mode: Mode) {
        editor = nil
        self.mode = mode

        switch mode {
        case .bookmarks:
            refresh()
        case .history:
            history.reset()
        case .copyHistory:
            copyHistory.reset()
        }
    }

    var nextMode: Mode {
        switch mode {
        case .bookmarks: return .history
        case .history: return .copyHistory
        case .copyHistory: return .bookmarks
        }
    }

    var previousMode: Mode {
        switch mode {
        case .bookmarks: return .copyHistory
        case .history: return .bookmarks
        case .copyHistory: return .history
        }
    }

    /// Tab and the right arrow do the same thing.
    func cycleMode() {
        show(nextMode)
    }

    func cycleModeBackwards() {
        show(previousMode)
    }

    func presentEditor(existing: Bookmark?, initialPath: String) {
        editor = EditorRequest(bookmark: existing, initialPath: initialPath)
    }

    func dismissEditor() {
        editor = nil
        refresh()
    }

    /// The path a new bookmark starts with: the last path Alt Right saw, then
    /// the clipboard. Same preference the full window uses for its “+” button.
    var suggestedPath: String {
        BookmarkCoordinator.shared.suggestedNewBookmarkPath()
    }

    /// Called again once the popover is actually on screen; the field can only
    /// become first responder after its window exists.
    func requestFocus() {
        focusGeneration += 1
    }

    func refresh() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = BookmarkRanker.arrange(
            store.bookmarks,
            query: trimmed,
            sort: sort
        )
        // No truncation: the list shows every bookmark (matching the query, if
        // any), so adding one never pushes an older one out of view.
        results = ranked

        if let selectedID, results.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = results.first?.id
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].id
        requestScroll(to: selectedID)
    }

    func select(_ bookmark: Bookmark) {
        // Click selection: no scroll request, the row must stay in place.
        selectedID = bookmark.id
    }

    private func requestScroll(to id: Bookmark.ID?) {
        guard let id else { return }
        scrollGeneration += 1
        scrollRequest = ScrollRequest(id: id, generation: scrollGeneration)
    }

    /// Opens a row and records the use for ranking. Returns false when the
    /// path is gone; the opener then offers Edit/Remove through the closures.
    @discardableResult
    func open(
        _ bookmark: Bookmark,
        onEdit: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> Bool {
        BookmarkCoordinator.shared.open(
            bookmark,
            onEdit: onEdit,
            onRemove: onRemove
        )
    }

    func togglePin(_ bookmark: Bookmark) {
        store.setPinned(!bookmark.pinned, path: bookmark.path)
    }
}
