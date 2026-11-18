import AppKit
import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var path: String
    var date: Date

    var id: String { path }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var lastError: String?

    let fileURL: URL
    private let limit = 250

    init(fileURL: URL = HistoryStore.defaultFileURL) {
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
            .appendingPathComponent("history.json", isDirectory: false)
    }

    func load() {
        do {
            entries = try read()
            lastError = nil
        } catch {
            entries = []
            lastError = "Could not read copied-path history.\n\n\(error.localizedDescription)"
        }
    }

    func record(paths: [String]) {
        let normalized = paths.compactMap(Bookmark.normalizedPath)
        guard !normalized.isEmpty else { return }

        // Add in reverse so a multi-line copy keeps its original order at the top.
        for path in normalized.reversed() {
            entries.removeAll { $0.path == path }
            entries.insert(HistoryEntry(path: path, date: Date()), at: 0)
        }

        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }

        persist()
    }

    func remove(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        entries.removeAll { paths.contains($0.path) }
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

    private func read() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
        return Array(decoded.prefix(limit))
    }
}
