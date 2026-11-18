import Foundation

/// A saved folder, file, or URL. `path` is the identity, so a duplicate path
/// updates the existing entry instead of creating a second one.
struct Bookmark: Codable, Identifiable, Hashable {
    var path: String
    var title: String
    var description: String

    var id: String { path }

    init(path: String, title: String, description: String = "") {
        self.path = path
        self.title = title
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case title
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    /// Normalizes user input into the form stored on disk. Returns nil for
    /// relative or malformed paths.
    static func normalizedPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard URL(string: trimmed) != nil else { return nil }
            return trimmed
        }

        if lower.hasPrefix("file://") {
            guard let url = URL(string: trimmed) else { return nil }
            return absolutePath(url.path(percentEncoded: false))
        }

        if lower.hasPrefix("smb://") {
            guard let components = URLComponents(string: trimmed) else { return nil }
            let encodedPath = components.percentEncodedPath
            let decodedPath = encodedPath.removingPercentEncoding ?? components.path
            return absolutePath("/Volumes" + decodedPath)
        }

        return absolutePath((trimmed as NSString).expandingTildeInPath)
    }

    private static func absolutePath(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let result = url.path
        return result.isEmpty ? nil : result
    }

    static func automaticTitle(for path: String) -> String {
        if let url = URL(string: path),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url.host ?? path
        }

        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }
}
