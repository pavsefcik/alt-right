import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    @State private var selection = Set<String>()
    @State private var alert: AlertMessage?
    @State private var clearRequested = false
    @State private var reportedError = false

    private var selectedEntries: [HistoryEntry] {
        store.entries.filter { selection.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(store.entries) { entry in
                        row(for: entry)
                            .tag(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                open([entry])
                            }
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
            }

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
        }
        .onChange(of: store.entries) { _ in
            let existing = Set(store.entries.map(\.path))
            selection = selection.filter { existing.contains($0) }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("No copied paths yet"))
                .font(.headline)
            Text(L("Use Copy Path in Finder or the menu bar and it will appear here."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func row(for entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)

            Text(entry.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(entry.date, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(String(format: L("%d copied paths"), store.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Button(L("Copy")) {
                copy(selectedEntries)
            }
            .disabled(selection.isEmpty)

            Button(L("Open")) {
                open(selectedEntries)
            }
            .disabled(selection.isEmpty)

            Button(L("Remove")) {
                store.remove(paths: selection)
                selection = []
            }
            .disabled(selection.isEmpty)

            Button(L("Clear History")) {
                clearRequested = true
            }
            .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copy(_ entries: [HistoryEntry]) {
        guard !entries.isEmpty else { return }
        let text = entries.map(\.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func open(_ entries: [HistoryEntry]) {
        for entry in entries {
            BookmarkOpener.open(path: entry.path)
        }
    }
}
