import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    @State private var filter = ""
    @State private var selection = Set<String>()
    @State private var alert: AlertMessage?
    @State private var clearRequested = false
    @State private var reportedError = false
    @FocusState private var searchFocused: Bool

    private var filtered: [HistoryEntry] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.path.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var selectedEntries: [HistoryEntry] {
        let paths = selection
        return store.entries.filter { paths.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 390)
        .onAppear {
            store.load()
            if !reportedError, let error = store.lastError {
                reportedError = true
                alert = AlertMessage(title: L("Could Not Read History"), message: error)
            }
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onChange(of: store.entries) { _ in
            let existing = Set(store.entries.map(\.path))
            selection = selection.filter { existing.contains($0) }
        }
        .onKeyPress(phases: .down) { press in
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
        .alert(L("Clear Copied Path History?"), isPresented: $clearRequested) {
            Button(L("Clear History"), role: .destructive) {
                store.clear()
                selection = []
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Every copied path will be removed from History. Bookmarks are not affected."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: L("Filter copied paths"),
                text: $filter,
                focus: $searchFocused,
                onSubmit: openSelection
            )
            .frame(maxWidth: 340)

            Spacer(minLength: 8)

            Text(copiedPathsLabel(store.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            emptyState(
                title: L("No copied paths yet"),
                message: L("Use Copy Path in Finder — or just press ⌥⌘C — and it will appear here.")
            )
        } else if filtered.isEmpty {
            emptyState(
                title: L("No matches"),
                message: L("Try a different filter.")
            )
        } else {
            List(selection: $selection) {
                ForEach(filtered) { entry in
                    row(for: entry)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        // Simultaneous, not exclusive: a plain
                        // .onTapGesture(count: 2) on a List row swallows the
                        // mouse-down the List needs, so single clicks stopped
                        // selecting and every footer button stayed disabled.
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { open([entry]) }
                        )
                        .contextMenu {
                            Button(L("Copy")) {
                                copy([entry])
                            }
                            Button(L("Open")) {
                                open([entry])
                            }
                            Divider()
                            Button(L("Remove"), role: .destructive) {
                                store.remove(paths: [entry.path])
                            }
                        }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                openSelection()
                return .handled
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
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

    private func row(for entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: pathSymbol(entry.path))

            Text(entry.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            AgeLabel(date: entry.date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                addSelection()
            } label: {
                Label(L("Add"), systemImage: "plus")
            }
            .disabled(selection.isEmpty)
            .help(L("Add the selected path as a bookmark"))

            Spacer(minLength: 12)

            Button(L("Copy")) {
                copy(selectedEntries)
            }
            .disabled(selection.isEmpty)

            Button(L("Remove")) {
                store.remove(paths: selection)
                selection = []
            }
            .disabled(selection.isEmpty)

            Button(L("Open")) {
                openSelection()
            }
            .keyboardShortcut("o")
            .disabled(selection.isEmpty)
            .help(L("Open (⌘O)"))

            Divider()
                .frame(height: 18)

            Button(L("Clear History")) {
                clearRequested = true
            }
            .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func copiedPathsLabel(_ count: Int) -> String {
        // "%d copied paths" with count 1 reads "1 copied paths"; keys are the
        // English text, so the singular is just another key.
        count == 1
            ? String(format: L("%d copied path"), 1)
            : String(format: L("%d copied paths"), count)
    }

    /// The Add button works on the list, not on whatever the clipboard happens
    /// to hold: one selected path opens the editor with that path, several are
    /// added in one go (they get their file names as titles, as in Finder).
    private func addSelection() {
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }

        if paths.count == 1, let path = paths.first {
            BookmarkCoordinator.shared.presentNewBookmark(initialPath: path)
        } else {
            BookmarkCoordinator.shared.handleAdd(paths: paths)
        }
    }

    private func copy(_ entries: [HistoryEntry]) {
        guard !entries.isEmpty else { return }
        let text = entries.map(\.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func openSelection() {
        guard !selectedEntries.isEmpty else { return }
        open(selectedEntries)
    }

    private func open(_ entries: [HistoryEntry]) {
        for entry in entries {
            BookmarkOpener.open(path: entry.path)
        }
    }
}

/// "Just now" / "5 min. ago" / "yesterday", refreshed on its own.
///
/// `Text(date, style: .relative)` renders sub-minute differences as "in 0
/// seconds" — an entry recorded a moment ago read as if it were in the future —
/// and it only refreshes on a coarse schedule. This is explicit about both.
private struct AgeLabel: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.text(for: date, now: context.date))
                .monospacedDigit()
        }
    }

    static func text(for date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return L("Just now") }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
