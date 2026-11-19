import SwiftUI

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct BookmarkSearchView: View {
    @ObservedObject var store: BookmarkStore

    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var alert: AlertMessage?
    @State private var deleteRequested = false
    @State private var reportedStoreError = false
    @FocusState private var searchFocused: Bool

    private var filtered: [Bookmark] {
        FuzzyMatcher.filter(query, in: store.bookmarks)
    }

    private var selectedBookmarks: [Bookmark] {
        let paths = selection
        return store.bookmarks.filter { paths.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            store.load()
            reportStoreErrorIfNeeded()
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onChange(of: store.bookmarks) { _ in
            let existing = Set(store.bookmarks.map(\.path))
            selection = selection.filter { existing.contains($0) }
        }
        .onKeyPress(phases: .down) { press in
            // ⌘F focuses the field even when the list has focus.
            guard press.key == "f", press.modifiers.contains(.command) else {
                return .ignored
            }
            searchFocused = true
            return .handled
        }
        .alert(item: $alert) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text(L("OK")))
            )
        }
        .alert(L("Delete Bookmarks"), isPresented: $deleteRequested) {
            Button(L("Delete"), role: .destructive) {
                deleteSelection()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: L("Search bookmarks"),
                text: $query,
                focus: $searchFocused,
                onSubmit: openSelection
            )
            .frame(maxWidth: 360)

            Spacer(minLength: 8)

            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.bookmarks.isEmpty {
            emptyState(
                title: L("No bookmarks yet"),
                message: L("Add bookmarks from Finder or with the Add Bookmark button.")
            )
        } else if filtered.isEmpty {
            emptyState(
                title: L("No matches"),
                message: L("Try a different search.")
            )
        } else {
            List(selection: $selection) {
                ForEach(filtered) { bookmark in
                    BookmarkRow(bookmark: bookmark)
                        .tag(bookmark.id)
                        .contentShape(Rectangle())
                        // Simultaneous: an exclusive tap gesture on a List row
                        // eats the click the List needs for selection.
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { open([bookmark]) }
                        )
                        .contextMenu {
                            Button(L("Open")) {
                                open([bookmark])
                            }
                            Button(L("Edit")) {
                                BookmarkCoordinator.shared.presentEditor(for: bookmark)
                            }
                            Divider()
                            Button(L("Delete"), role: .destructive) {
                                selection = [bookmark.path]
                                deleteRequested = true
                            }
                        }
                }
            }
            .listStyle(.inset)
            // Return opens the selection when the list — not the field — has
            // focus. In the field, .onSubmit below does the same thing.
            .onKeyPress(.return) {
                openSelection()
                return .handled
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                BookmarkCoordinator.shared.presentNewBookmark()
            } label: {
                Label(L("Add"), systemImage: "plus")
            }
            .help(L("Add Bookmark"))

            Spacer(minLength: 12)

            Button(L("Edit")) {
                guard selectedBookmarks.count == 1, let bookmark = selectedBookmarks.first else {
                    return
                }
                BookmarkCoordinator.shared.presentEditor(for: bookmark)
            }
            .disabled(selectedBookmarks.count != 1)
            .help(L("Edit Bookmark"))

            Button(L("Delete")) {
                deleteRequested = true
            }
            .disabled(selection.isEmpty)
            .help(L("Delete"))

            Button(L("Open")) {
                openSelection()
            }
            .keyboardShortcut("o")
            .disabled(selection.isEmpty)
            .help(L("Open (⌘O)"))
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var countLabel: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return countText(store.bookmarks.count)
        }
        return String(
            format: L("%d of %d bookmarks"),
            filtered.count,
            store.bookmarks.count
        )
    }

    private func countText(_ count: Int) -> String {
        count == 1
            ? String(format: L("%d bookmark"), 1)
            : String(format: L("%d bookmarks"), count)
    }

    private var deleteMessage: String {
        let count = selection.count
        if count == 1 {
            return L("This bookmark will be removed. This cannot be undone.")
        }
        return String(
            format: L("%d bookmarks will be removed. This cannot be undone."),
            count
        )
    }

    private func openSelection() {
        guard !selectedBookmarks.isEmpty else { return }
        open(selectedBookmarks)
    }

    private func open(_ bookmarks: [Bookmark]) {
        for bookmark in bookmarks {
            BookmarkOpener.open(
                bookmark,
                onEdit: {
                    BookmarkCoordinator.shared.presentEditor(for: bookmark)
                },
                onRemove: {
                    remove(paths: [bookmark.path])
                }
            )
        }
    }

    private func deleteSelection() {
        remove(paths: selection)
    }

    private func remove(paths: Set<String>) {
        do {
            try store.remove(paths: paths)
            selection.subtract(paths)
        } catch {
            alert = AlertMessage(
                title: L("Could Not Delete"),
                message: error.localizedDescription
            )
        }
    }

    private func reportStoreErrorIfNeeded() {
        guard !reportedStoreError, let error = store.lastError else { return }
        reportedStoreError = true
        alert = AlertMessage(title: L("Could Not Read Bookmarks"), message: error)
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: pathSymbol(bookmark.path))

            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if !bookmark.description.isEmpty {
                    Text(bookmark.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(bookmark.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
