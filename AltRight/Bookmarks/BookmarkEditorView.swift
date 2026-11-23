import AppKit
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
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text(existing == nil ? L("Add Bookmark") : L("Edit Bookmark"))
                .font(.system(size: 17, weight: .semibold))

            labelled(L("Folder, file, or URL")) {
                HStack(spacing: 8) {
                    PathTextField(
                        text: $path,
                        wantsInitialFocus: existing == nil,
                        accessibilityLabel: L("Folder, file, or URL")
                    )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(
                                    errorMessage == nil ? Color.clear : Color.red,
                                    lineWidth: 1
                                )
                        )

                    // Pasting a path is fine, but finding the folder in the
                    // first place is what the Finder is for.
                    Button(L("Browse…")) {
                        browse()
                    }
                    .buttonStyle(PanelButtonStyle())
                }
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
            .buttonStyle(PanelButtonStyle())

            Button(existing == nil ? L("Add Bookmark") : L("Save")) {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PanelButtonStyle())
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
            description: trimmedDescription,
            // Editing the path or title must not wipe the use history the
            // relevance ranking relies on.
            lastOpenedAt: existing?.lastOpenedAt,
            openCount: existing?.openCount ?? 0,
            pinned: existing?.pinned ?? false
        )

        do {
            if let existing {
                // Rewrite the bookmark the editor was opened for; never leave
                // the old path behind as a second entry.
                try store.replace(originalPath: existing.path, with: bookmark)
            } else {
                _ = try store.upsert(bookmark)
            }
            onSave(bookmark)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the standard file panel and writes the choice straight into the
    /// editor. App-modal is deliberate: the all-in-one panel is managed by
    /// hand, so a modal panel does not dismiss it.
    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = L("Choose")
        panel.message = L("Choose a folder or file to bookmark.")

        if let normalized = Bookmark.normalizedPath(path), normalized.hasPrefix("/") {
            let url = URL(fileURLWithPath: normalized)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory) {
                panel.directoryURL = isDirectory.boolValue
                    ? url
                    : url.deletingLastPathComponent()
            }
        }

        AppActivation.activate()
        let response = panel.runModal()

        guard response == .OK, let url = panel.url else { return }

        let chosen = url.path(percentEncoded: false)
        let previousTitle = title
        let previousPath = path
        path = chosen
        errorMessage = nil
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || previousTitle == Bookmark.automaticTitle(for: previousPath) {
            title = Bookmark.automaticTitle(for: chosen)
        }

        AppDelegate.log("browse chose \(chosen)")
    }
}

/// A plain left-aligned field that keeps the *end* of a too-long path visible.
/// SwiftUI's TextField clips at the start when it is not being edited, which
/// hides the file name — the one part of the path the user needs to recognise.
private struct PathTextField: NSViewRepresentable {
    @Binding var text: String
    var wantsInitialFocus: Bool
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> PathField {
        let field = PathField()
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(accessibilityLabel)
        field.stringValue = text
        field.wantsInitialFocus = wantsInitialFocus
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: PathField, context: Context) {
        context.coordinator.text = $text
        field.setAccessibilityLabel(accessibilityLabel)
        if field.stringValue != text {
            field.stringValue = text
        }
        field.updateOverflowAlignment()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? PathField else { return }
            text.wrappedValue = field.stringValue
            field.updateOverflowAlignment()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            (notification.object as? PathField)?.updateOverflowAlignment()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.object as? PathField)?.updateOverflowAlignment()
        }
    }
}

private final class PathField: NSTextField {
    var wantsInitialFocus = false
    private var tookInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsInitialFocus, !tookInitialFocus, window != nil else { return }
        tookInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            if let editor = self.currentEditor() {
                let end = NSRange(location: (self.stringValue as NSString).length, length: 0)
                editor.selectedRange = end
                editor.scrollRangeToVisible(end)
            }
        }
    }

    override func layout() {
        super.layout()
        updateOverflowAlignment()
    }

    /// Left-aligned while the path fits; right-aligned only when it does not,
    /// so the beginning stays where the user expects and the end stays visible.
    func updateOverflowAlignment() {
        guard currentEditor() == nil else {
            alignment = .left
            return
        }
        let available = bounds.width - 10
        guard available > 0 else { return }
        let width = attributedStringValue.size().width
        alignment = width > available ? .right : .left
    }
}
