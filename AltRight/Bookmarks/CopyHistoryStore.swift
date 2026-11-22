import AppKit
import Foundation

/// One piece of text the user copied anywhere in macOS — the clipboard
/// history, kept the same way `HistoryStore` keeps copied paths.
struct CopyEntry: Codable, Identifiable, Hashable {
    var text: String
    var date: Date

    /// The text *is* the identity: copying the same thing twice moves the
    /// existing row to the top instead of adding a duplicate.
    var id: String { text }
}

@MainActor
final class CopyHistoryStore: ObservableObject {
    static let shared = CopyHistoryStore()

    @Published private(set) var entries: [CopyEntry] = []
    @Published private(set) var lastError: String?

    let fileURL: URL
    private let limit = 200

    /// Anything longer than this (a whole file, a wall of logs) is not
    /// something anyone pastes from a menu, and it would bloat the JSON.
    static let maxLength = 20_000

    init(fileURL: URL = CopyHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("Alt Right", isDirectory: true)
            .appendingPathComponent("copy-history.json", isDirectory: false)
    }

    func load() {
        do {
            entries = try read()
            lastError = nil
        } catch {
            entries = []
            lastError = "Could not read copy history.\n\n\(error.localizedDescription)"
        }
    }

    /// Records a copy, newest first. Whitespace-only text is ignored — it is
    /// never what the user meant to keep.
    func record(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxLength else {
            return
        }

        entries.removeAll { $0.text == text }
        entries.insert(CopyEntry(text: text, date: Date()), at: 0)

        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }

        persist()
    }

    func remove(texts: Set<String>) {
        guard !texts.isEmpty else { return }
        entries.removeAll { texts.contains($0.text) }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func read() throws -> [CopyEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        let decoded = try JSONDecoder().decode([CopyEntry].self, from: data)
        return Array(decoded.prefix(limit))
    }
}

/// Puts text on the general pasteboard — the one ⌘V reads.
@MainActor
enum ClipboardWriter {
    static func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Do not let the copy we just made count as a new copy of its own, or
        // re-using an old entry would silently reorder the list.
        PasteboardWatcher.shared.noteOwnWrite()
    }
}
