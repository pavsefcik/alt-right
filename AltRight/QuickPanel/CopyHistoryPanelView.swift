import AppKit
import SwiftUI

/// The Copy History face of the all-in-one panel: everything copied anywhere in
/// macOS, newest first, with filter, copy and clear.
struct CopyHistoryPanelView: View {
    @ObservedObject var model: CopyHistoryPanelModel
    let onShowPaths: () -> Void
    let onShowBookmarks: () -> Void

    @FocusState private var searchFocused: Bool

    @State private var lastClickID: CopyEntry.ID?
    @State private var lastClickAt = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .onAppear {
            model.reset()
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: L("Filter copies"),
                text: $model.query,
                focus: $searchFocused,
                onSubmit: copySelected
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.entries) { entry in
                            row(for: entry)
                                .id(entry.id)
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

    private func row(for entry: CopyEntry) -> some View {
        let selected = entry.id == model.selectedID
        // A copy whose whole text is one colour is still copied verbatim;
        // the swatch only decides how the row is drawn.
        let color = ColorLiteral.parse(entry.text)
        // Display only: the stored text, and what Copy puts back on the
        // pasteboard, is always `entry.text`.
        let preview = CopyPreview(text: entry.text)

        return HStack(spacing: 10) {
            if let color {
                ColorSwatch(color: color)
            } else {
                IconTile(symbol: "doc.on.doc")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(preview.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let detail = preview.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let color {
                    Text(color.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(entry.text.count == 1
                         ? L("1 character")
                         : String(format: L("%d characters"), entry.text.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowHighlight(selected: selected)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                guard abs(value.translation.width) < 3,
                      abs(value.translation.height) < 3 else {
                    return
                }
                handleClick(entry)
            }
        )
        .contextMenu {
            Button(L("Copy")) { copy(entry) }

            // A copy that happens to be a path can become a bookmark, exactly
            // like one picked from the path history.
            if Bookmark.normalizedPath(preview.title) != nil {
                Button(L("Add Bookmark…")) {
                    BookmarkCoordinator.shared.presentNewBookmark(
                        initialPath: Bookmark.normalizedPath(entry.text) ?? preview.title
                    )
                }
            }

            Divider()
            Button(L("Delete"), role: .destructive) { model.remove(entry) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isFiltering ? "magnifyingglass" : "doc.on.doc")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(model.isFiltering ? L("No matches") : L("No copies yet"))
                .font(.headline)

            if !model.isFiltering {
                Text(L("Copy any text and it appears here."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(L("Copy")) {
                copySelected()
            }
            .disabled(model.selected == nil)

            Button(L("Clear All")) {
                model.clearAll()
            }
            .disabled(model.entries.isEmpty)

            Spacer(minLength: 0)

            ModeNavButtons(
                previousTitle: L("Copied Paths"),
                nextTitle: L("Bookmarks"),
                onPrevious: onShowPaths,
                onNext: onShowBookmarks
            )
        }
        .buttonStyle(PanelButtonStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func handleClick(_ entry: CopyEntry) {
        let now = Date()
        if lastClickID == entry.id,
           now.timeIntervalSince(lastClickAt) < 0.4 {
            lastClickID = nil
            lastClickAt = .distantPast
            model.select(entry)
            copy(entry)
            return
        }

        lastClickID = entry.id
        lastClickAt = now
        model.select(entry)
    }

    private func copySelected() {
        guard let entry = model.selected else {
            NSSound.beep()
            return
        }
        copy(entry)
    }

    /// Copying is the errand: put the text back on the pasteboard and close, so
    /// the next ⌘V lands where the user was working.
    private func copy(_ entry: CopyEntry) {
        ClipboardWriter.write(entry.text)
        StatusItemController.shared.closePanel()
    }
}

/// Display-only flattening of a copied text for its row: the first line is the
/// headline, the rest follows it flattened onto one line. Every run of
/// whitespace — spaces, tabs, non-breaking spaces, any line break — collapses
/// to a single space and blank lines disappear, so the row stays tidy. Nothing
/// here touches the stored entry: copying the row writes the original text back
/// to the pasteboard unchanged.
private struct CopyPreview {
    let title: String
    let detail: String?

    init(text: String) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }

        title = lines.first ?? text
        detail = lines.count > 1
            ? lines.dropFirst().joined(separator: " ")
            : nil
    }
}
