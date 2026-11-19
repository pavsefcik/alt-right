import SwiftUI

struct BookmarkEditorView: View {
    @ObservedObject var store: BookmarkStore

    let existing: Bookmark?
    let initialPath: String
    let onSave: (Bookmark) -> Void
    let onCancel: () -> Void

    @State private var path: String
    @State private var title: String
    @State private var description: String
    @State private var errorMessage: String?
    @FocusState private var pathFocused: Bool

    init(
        store: BookmarkStore,
        existing: Bookmark?,
        initialPath: String,
        onSave: @escaping (Bookmark) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.store = store
        self.existing = existing
        self.initialPath = initialPath
        self.onSave = onSave
        self.onCancel = onCancel

        let path = existing?.path ?? initialPath
        let title = existing?.title ?? (path.isEmpty ? "" : Bookmark.automaticTitle(for: path))

        _path = State(initialValue: path)
        _title = State(initialValue: title)
        _description = State(initialValue: existing?.description ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 470)
        .onAppear {
            pathFocused = existing == nil
        }
        .onChange(of: path) { newValue in
            guard existing == nil else { return }
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = Bookmark.automaticTitle(for: newValue)
            }
        }
    }

    /// Left-aligned like the search and history windows: label above the field,
    /// fields flush with the 16 pt gutter, nothing centred or boxed off.
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelled(L("Path or URL")) {
                TextField(L("Path or URL"), text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .labelsHidden()
                    .focused($pathFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                errorMessage == nil ? Color.clear : Color.red,
                                lineWidth: 1
                            )
                    )
            }

            labelled(L("Title")) {
                TextField(L("Title"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            labelled(L("Description")) {
                TextEditor(text: $description)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            status
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelled<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if !path.isEmpty {
            Text(preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the bookmark points, in the user's words, before saving.
    private var preview: String {
        guard let normalized = Bookmark.normalizedPath(path) else {
            return L("Enter an absolute path, a file URL, an SMB URL, or an HTTP(S) URL.")
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: normalized,
            isDirectory: &isDirectory
        )
        if normalized.lowercased().hasPrefix("http") {
            return String(format: L("Opens in your browser: %@"), normalized)
        }
        if !exists {
            return String(format: L("Not on disk right now: %@"), normalized)
        }
        return isDirectory.boolValue
            ? String(format: L("Opens the folder: %@"), normalized)
            : String(format: L("Reveals the file: %@"), normalized)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button(L("Cancel")) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button(existing == nil ? L("Add Bookmark") : L("Save")) {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func save() {
        guard let normalized = Bookmark.normalizedPath(path) else {
            errorMessage = L("Enter an absolute path, a file URL, an SMB URL, or an HTTP(S) URL.")
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty
            ? Bookmark.automaticTitle(for: normalized)
            : trimmedTitle
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing,
           existing.path != normalized,
           store.hasPath(normalized) {
            errorMessage = L("A bookmark for this path already exists.")
            return
        }

        let bookmark = Bookmark(
            path: normalized,
            title: finalTitle,
            description: trimmedDescription
        )

        do {
            _ = try store.upsert(bookmark)
            onSave(bookmark)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
