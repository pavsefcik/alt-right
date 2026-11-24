import AppKit
import SwiftUI

/// The left-click surface: the whole bookmark/history window, not a small
/// launcher. Bookmarks and History are two faces of the same panel; adding and
/// editing happen inline; deleting is a multi-select mode in the same list.
struct QuickPanelView: View {
    @ObservedObject var model: QuickPanelModel

    /// Called after a form that was opened by Finder saves. That is the end of
    /// the errand, so the panel closes; a form opened here stays open.
    var onEditorSaved: () -> Void = {}

    @FocusState private var searchFocused: Bool

    @State private var lastClickID: Bookmark.ID?
    @State private var lastClickAt = Date.distantPast

    var body: some View {
        Group {
            if let request = model.editor {
                BookmarkEditorView(
                    store: model.bookmarkStore,
                    existing: request.bookmark,
                    initialPath: request.initialPath,
                    onSave: { bookmark in
                        // A form opened by Finder is done once it saves; one
                        // opened from the list returns to the list with the
                        // saved row selected, like any native list window.
                        let closing = request.closeAfterSave
                        model.dismissEditor()
                        if closing {
                            onEditorSaved()
                        } else {
                            model.focus(bookmark)
                            focusSearchField()
                        }
                    },
                    onCancel: {
                        model.dismissEditor()
                        focusSearchField()
                    },
                    onReveal: { bookmark in
                        model.dismissEditor()
                        model.focus(bookmark)
                        focusSearchField()
                    }
                )
                .id(request.id)
            } else if model.mode == .history {
                HistoryPanelView(
                    model: model.history,
                    onShowBookmarks: {
                        model.showBookmarks()
                        focusSearchField()
                    },
                    onShowCopyHistory: {
                        model.showCopyHistory()
                        focusSearchField()
                    }
                )
            } else if model.mode == .copyHistory {
                CopyHistoryPanelView(
                    model: model.copyHistory,
                    onShowPaths: {
                        model.showHistory()
                        focusSearchField()
                    },
                    onShowBookmarks: {
                        model.showBookmarks()
                        focusSearchField()
                    }
                )
            } else {
                bookmarksView
            }
        }
        .frame(width: 600, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: focusSearchField)
        .onChange(of: model.focusGeneration) { _ in
            focusSearchField()
        }
        .onChange(of: model.mode) { _ in
            endDeleteMode()
        }
    }

    // MARK: - Bookmarks

    private var bookmarksView: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SearchField(
                placeholder: L("Search bookmarks"),
                text: $model.query,
                focus: $searchFocused,
                onSubmit: openSelected
            )

            SortPopUpButton(selection: $model.sort)
                .help(L("Sort bookmarks"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var content: some View {
        if model.results.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.results) { bookmark in
                            row(for: bookmark)
                                .id(bookmark.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.scrollRequest) { request in
                    guard let request else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(for bookmark: Bookmark) -> some View {
        let selected = bookmark.id == model.selectedID
        let checked = model.deleteSelection.contains(bookmark.id)

        return HStack(spacing: 10) {
            if model.deleteMode {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                    .padding(.leading, 2)
            }

            IconTile(symbol: pathSymbol(bookmark.path))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(bookmark.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if bookmark.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !bookmark.description.isEmpty {
                    Text(bookmark.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(bookmark.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowHighlight(selected: selected && !model.deleteMode)
        .contentShape(Rectangle())
        // Selection is immediate; a second click on the same row inside the
        // double-click interval opens it. Detecting the pair here (instead of
        // relying on TapGesture(count: 2)) keeps both behaviours reliable
        // inside the ScrollView.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                guard abs(value.translation.width) < 3,
                      abs(value.translation.height) < 3 else {
                    return
                }
                handleClick(bookmark)
            }
        )
        .contextMenu {
            if !model.deleteMode {
                Button(L("Open")) { open(bookmark) }
                Button(L("Edit")) { edit(bookmark) }
                Button(bookmark.pinned ? L("Unpin") : L("Pin")) {
                    model.togglePin(bookmark)
                }
                Divider()
                Button(L("Copy Path")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(bookmark.path, forType: .string)
                }
                Divider()
                Button(L("Delete"), role: .destructive) {
                    model.beginDeleteMode(with: bookmark)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isSearching ? "magnifyingglass" : "bookmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(model.isSearching ? L("No matches") : L("No bookmarks yet"))
                .font(.headline)

            if !model.isSearching {
                Text(L("Add one from Finder or with Add Bookmark."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if model.deleteMode {
            deleteFooter
        } else {
            HStack(spacing: 14) {
                Button {
                    model.presentEditor(existing: nil, initialPath: model.suggestedPath)
                } label: {
                    Label(L("Add"), systemImage: "plus")
                }
                .help(L("Add Bookmark"))

                Button(L("Edit")) {
                    guard let bookmark = model.selectedResult else { return }
                    edit(bookmark)
                }
                .disabled(model.selectedResult == nil)
                .help(L("Edit Bookmark"))

                Button(L("Delete")) {
                    model.beginDeleteMode(with: model.selectedResult)
                }
                .disabled(model.selectedResult == nil)
                .help(L("Delete"))

                Button(L("Open")) {
                    openSelected()
                }
                .disabled(model.selectedResult == nil)
                .help(L("Open"))

                Spacer(minLength: 0)

                ModeNavButtons(
                    previousTitle: L("Copies"),
                    nextTitle: L("Copied Paths"),
                    onPrevious: {
                        model.showCopyHistory()
                        focusSearchField()
                    },
                    onNext: {
                        model.showHistory()
                        focusSearchField()
                    }
                )
            }
            .buttonStyle(PanelButtonStyle())
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var deleteFooter: some View {
        HStack(spacing: 14) {
            Button(model.deleteButtonTitle) {
                model.performDelete()
            }
            .disabled(model.deleteSelection.isEmpty)

            Button(model.allSelected ? L("Deselect All") : L("Select All")) {
                if model.allSelected {
                    model.deleteSelection.removeAll()
                } else {
                    model.deleteSelection = Set(model.results.map(\.id))
                }
            }
            .disabled(model.results.isEmpty)

            Spacer(minLength: 0)

            Button(L("Cancel")) {
                endDeleteMode()
            }
        }
        .buttonStyle(PanelButtonStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func handleClick(_ bookmark: Bookmark) {
        if model.deleteMode {
            model.toggleDelete(bookmark)
            return
        }

        let now = Date()
        if lastClickID == bookmark.id,
           now.timeIntervalSince(lastClickAt) < 0.4 {
            lastClickID = nil
            lastClickAt = .distantPast
            model.select(bookmark)
            open(bookmark)
            return
        }

        lastClickID = bookmark.id
        lastClickAt = now
        model.select(bookmark)
        focusSearchField()
    }

    // MARK: - Delete mode

    private func endDeleteMode() {
        model.endDeleteMode()
        lastClickID = nil
        lastClickAt = .distantPast
    }

    // MARK: - Actions

    private func focusSearchField() {
        // The popover window becomes key only after it is on screen; focusing
        // before that leaves the field unfocused and the first keystroke lost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            searchFocused = true
        }
    }

    private func openSelected() {
        guard !model.deleteMode, let bookmark = model.selectedResult else {
            NSSound.beep()
            return
        }
        open(bookmark)
    }

    private func open(_ bookmark: Bookmark) {
        StatusItemController.shared.closePanel(reason: "open bookmark (view)")
        model.open(
            bookmark,
            onEdit: {
                StatusItemController.shared.showPanel(editing: bookmark)
            },
            onRemove: {
                BookmarkCoordinator.shared.removeBookmark(path: bookmark.path)
            }
        )
    }

    private func edit(_ bookmark: Bookmark) {
        model.presentEditor(existing: bookmark, initialPath: bookmark.path)
    }
}


/// Native pop-up button: one click opens the list, the width never changes
/// with the selected title (so the search field does not jump), and it is the
/// same control macOS uses everywhere else.
private struct SortPopUpButton: NSViewRepresentable {
    @Binding var selection: BookmarkSort

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: BookmarkSort.allCases.map(\.title))
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 138).isActive = true
        if let index = BookmarkSort.allCases.firstIndex(of: selection) {
            button.selectItem(at: index)
        }
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        guard let index = BookmarkSort.allCases.firstIndex(of: selection),
              button.indexOfSelectedItem != index else {
            return
        }
        button.selectItem(at: index)
    }

    final class Coordinator: NSObject {
        var selection: Binding<BookmarkSort>

        init(selection: Binding<BookmarkSort>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard BookmarkSort.allCases.indices.contains(index) else { return }
            selection.wrappedValue = BookmarkSort.allCases[index]
        }
    }
}
