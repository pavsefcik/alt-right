import Combine
import Foundation

/// State for the History face of the all-in-one panel.
@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published var query = "" {
        didSet { refresh() }
    }

    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var selectedID: String?

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

    let store: HistoryStore
    private var observer: AnyCancellable?

    init(store: HistoryStore) {
        self.store = store

        observer = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var selected: HistoryEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reset() {
        store.load()
        query = ""
        refresh()
    }

    func refresh() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty {
            entries = store.entries
        } else {
            entries = store.entries.filter {
                $0.path.range(
                    of: needle,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
        }

        if let selectedID, entries.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = entries.first?.id
    }

    func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), entries.count - 1)
        selectedID = entries[next].id
        requestScroll(to: selectedID)
    }

    func select(_ entry: HistoryEntry) {
        // Click selection: no scroll request, the row must stay in place.
        selectedID = entry.id
    }

    private func requestScroll(to id: String?) {
        guard let id else { return }
        scrollGeneration += 1
        scrollRequest = ScrollRequest(id: id, generation: scrollGeneration)
    }

    func remove(_ entry: HistoryEntry) {
        store.remove(paths: [entry.path])
        refresh()
    }

    func clearAll() {
        store.clear()
        refresh()
    }
}
