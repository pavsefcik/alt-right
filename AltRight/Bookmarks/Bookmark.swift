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
    ///
    /// The input usually comes from somewhere that adds noise of its own: a
    /// shell wraps paths in `'…'`, Finder's drag-and-drop hands over a `file://`
    /// URL, a chat message escapes spaces as `My\ Folder`, and a colleague
    /// sends an `smb://` URL. All of those describe a local path, so they are
    /// reduced to one.
    static func normalizedPath(_ raw: String) -> String? {
        var text = stripQuotes(raw)
        guard !text.isEmpty else { return nil }

        // A filename may genuinely end in a quote character (`…/McDonald's`).
        // If the unstripped string is a real path and the stripped one is not,
        // the quote belonged to the name, not to the paste.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != text,
           trimmed.hasPrefix("/"),
           FileManager.default.fileExists(atPath: trimmed),
           !FileManager.default.fileExists(atPath: text) {
            text = trimmed
        }

        if let scheme = scheme(of: text) {
            switch scheme {
            case "http", "https":
                return webURL(text)
            case "file":
                return fileURLPath(text)
            case "smb", "afp", "cifs", "nfs", "webdav":
                return networkURLPath(text)
            default:
                // `notes:…` is not a path; neither is any other unknown scheme.
                return nil
            }
        }

        return filePath(text)
    }

    // MARK: - Input cleaning

    /// Trims whitespace and removes the quotes wrapping a pasted path. Both
    /// sides are stripped independently, so `'/Users/me/x` (a lost closing
    /// quote) and `/Users/me/x'` clean up the same way.
    private static func stripQuotes(_ raw: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"'`\u{2018}\u{2019}\u{201C}\u{201D}")
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        while let first = text.unicodeScalars.first, quotes.contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while let last = text.unicodeScalars.last, quotes.contains(last) {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    /// `My\ Folder` → `My Folder`, but only when the backslash really is an
    /// escape. A filename with a literal backslash is left alone.
    private static func shellUnescaped(_ text: String) -> String? {
        let escapable = Set(" \t()[]{}&$!;*?<>|~#'\"")
        var result = ""
        var changed = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            if escapable.contains(next) {
                result.append(next)
                changed = true
            } else {
                result.append(character)
                result.append(next)
            }
        }

        return changed ? result : nil
    }

    /// The URL scheme, if the string starts with one. A POSIX path that contains
    /// a colon further down (`/Users/a:b`) is not mistaken for a scheme.
    private static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let prefix = text[..<colon]
        guard let first = prefix.first, first.isLetter else { return nil }
        guard prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return nil
        }
        return prefix.lowercased()
    }

    // MARK: - URLs

    private static func webURL(_ text: String) -> String? {
        if let url = URL(string: text), url.host != nil {
            // `absoluteString` encodes spaces, which `URL(string:)` accepts
            // leniently but `NSWorkspace.open` would reject.
            return url.absoluteString
        }
        // Spaces in an address from a chat message are common; encode just
        // enough for Foundation to accept it.
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded),
           url.host != nil {
            return encoded
        }
        return nil
    }

    private static func fileURLPath(_ text: String) -> String? {
        var candidates: [String] = [text]
        if !text.contains("%"),
           let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            candidates.append(encoded)
        }

        for candidate in candidates where !candidate.isEmpty {
            guard let url = URL(string: candidate), url.isFileURL else { continue }
            let path = url.path(percentEncoded: false)
            guard !path.isEmpty else { continue }
            // A remote `file://server/share` URL means the mounted volume.
            if let host = url.host, !host.isEmpty, host.lowercased() != "localhost" {
                return networkVolumePath(path)
            }
            if let normalized = absolutePath(path) {
                return normalized
            }
        }

        // `URL(string:)` refuses unescaped spaces; fall back to the raw text.
        var rest = text
        for prefix in ["file://", "file:"] where rest.lowercased().hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        if !rest.hasPrefix("/") {
            rest = "/" + rest
        }
        return filePath(rest.removingPercentEncoding ?? rest)
    }

    /// An `smb://server/share/folder` URL points at `/Volumes/share/folder` on
    /// a Mac where the share is mounted under its own name.
    private static func networkURLPath(_ text: String) -> String? {
        var components = URLComponents(string: text)
        if components == nil,
           let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components = URLComponents(string: encoded)
        }

        guard let components else { return nil }
        return networkVolumePath(
            components.percentEncodedPath.removingPercentEncoding ?? components.path
        )
    }

    private static func networkVolumePath(_ path: String) -> String? {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "/" else { return nil }

        let withSlash = path.hasPrefix("/") ? path : "/" + path
        return absolutePath("/Volumes" + withSlash)
    }

    // MARK: - Filesystem paths

    private static func filePath(_ text: String) -> String? {
        var existing: [String] = []
        var absolute: [String] = []

        var variants = [text]
        if let unescaped = shellUnescaped(text), unescaped != text {
            variants.append(unescaped)
        }
        if text.contains("%"), let decoded = text.removingPercentEncoding, decoded != text {
            variants.append(decoded)
        }

        for variant in variants {
            let expanded = (variant as NSString).expandingTildeInPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expanded.isEmpty else { continue }

            if expanded.hasPrefix("/") {
                if let path = absolutePath(expanded) {
                    absolute.append(path)
                    if FileManager.default.fileExists(atPath: path) {
                        existing.append(path)
                    }
                }
            } else if expanded.contains("/"),
                      let path = absolutePath("/" + expanded),
                      FileManager.default.fileExists(atPath: path) {
                // A leading slash lost in transit (`Users/me/Documents`) is
                // only accepted when the result really exists — otherwise
                // any prose with a slash in it would become a path.
                existing.append(path)
            }
        }

        // Prefer the form that exists on disk: the escaped variant pointing at
        // nothing loses to the unescaped variant pointing at the file.
        if let match = existing.first {
            return match
        }
        // Nothing on disk (a bookmark may point at a folder that is not
        // mounted right now): prefer the un-escaped/decoded variant, which is
        // what the user meant, over the shell-escaped original.
        return absolute.last
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
