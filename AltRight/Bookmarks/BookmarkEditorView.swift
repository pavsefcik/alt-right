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
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? L("Add Bookmark") : L("Edit Bookmark"))
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Path or URL"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L("Path or URL"), text: $path)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L("Title"), text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .font(.body)
                    .frame(height: 78)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(L("Save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 470)
        .onChange(of: path) { newValue in
            guard existing == nil else { return }
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = Bookmark.automaticTitle(for: newValue)
            }
        }
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
