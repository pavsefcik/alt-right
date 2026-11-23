import AppKit
import SwiftUI

/// The History face of the all-in-one panel. Same window, different list:
/// copied paths with filter, copy/open/bookmark/delete and a way back.
struct HistoryPanelView: View {
    @ObservedObject var model: HistoryPanelModel
    let onShowBookmarks: () -> Void
    let onShowCopyHistory: () -> Void

    @FocusState private var searchFocused: Bool

    @State private var lastClickID: HistoryEntry.ID?
    @State private var lastClickAt = Date.distantPast
    @State private var showCopied = false
    @State private var copyToastTask: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .overlay(alignment: .bottom) {
            if showCopied {
                CopyConfirmationToast()
                    .padding(.bottom, 52)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
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
                placeholder: L("Filter copied paths"),
                text: $model.query,
                focus: $searchFocused,
                onSubmit: openSelected
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

    private func row(for entry: HistoryEntry) -> some View {
        let selected = entry.id == model.selectedID

        return HStack(spacing: 10) {
            IconTile(symbol: "clock.arrow.circlepath")

            VStack(alignment: .leading, spacing: 1) {
                Text(Bookmark.automaticTitle(for: entry.path))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(entry.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            Button(L("Copy Path")) { copy(entry) }
            Button(L("Open")) { open(entry) }
            Button(L("Add Bookmark…")) {
                BookmarkCoordinator.shared.presentNewBookmark(initialPath: entry.path)
            }
            Divider()
            Button(L("Delete"), role: .destructive) { model.remove(entry) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isFiltering ? "magnifyingglass" : "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(model.isFiltering ? L("No matches") : L("No copied paths yet"))
                .font(.headline)

            if !model.isFiltering {
                Text(L("Use Copy Path in Finder — or press ⌥⌘C — and it appears here."))
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
            Button(L("+ Bookmark")) {
                guard let entry = model.selected else { return }
                BookmarkCoordinator.shared.presentNewBookmark(initialPath: entry.path)
            }
            .disabled(model.selected == nil)

            Button(L("Copy")) {
                guard let entry = model.selected else { return }
                copy(entry)
            }
            .disabled(model.selected == nil)

            Button(L("Clear All")) {
                model.clearAll()
            }
            .disabled(model.entries.isEmpty)

            Button(L("Open")) {
                openSelected()
            }
            .disabled(model.selected == nil)

            Spacer(minLength: 0)

            ModeNavButtons(
                previousTitle: L("Bookmarks"),
                nextTitle: L("Copies"),
                onPrevious: onShowBookmarks,
                onNext: onShowCopyHistory
            )
        }
        .buttonStyle(PanelButtonStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func handleClick(_ entry: HistoryEntry) {
        let now = Date()
        if lastClickID == entry.id,
           now.timeIntervalSince(lastClickAt) < 0.4 {
            lastClickID = nil
            lastClickAt = .distantPast
            model.select(entry)
            open(entry)
            return
        }

        lastClickID = entry.id
        lastClickAt = now
        model.select(entry)
    }

    private func openSelected() {
        guard let entry = model.selected else {
            NSSound.beep()
            return
        }
        open(entry)
    }

    private func open(_ entry: HistoryEntry) {
        StatusItemController.shared.closePanel()
        BookmarkOpener.open(path: entry.path)
    }

    private func copy(_ entry: HistoryEntry) {
        ClipboardWriter.write(entry.path)
        showCopiedConfirmation()
    }

    private func showCopiedConfirmation() {
        copyToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            showCopied = true
        }

        let task = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.18)) {
                showCopied = false
            }
        }
        copyToastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }
}
