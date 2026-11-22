import Foundation

/// The order a bookmark list is shown in. Relevance is the default everywhere;
/// the full Bookmarks window also offers a stable alphabetical and a
/// last-used order.
enum BookmarkSort: String, CaseIterable, Identifiable {
    case relevance
    case name
    case recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return L("Relevance")
        case .name: return L("Name")
        case .recentlyAdded: return L("Recently Added")
        }
    }
}

/// Turns the stored bookmark order into the order a human wants to see.
///
/// `FuzzyMatcher` decides *whether* a bookmark matches; this decides *where*
/// it goes. Splitting the two is what keeps ranking explainable: every query
/// word still has to match, and the score only orders the survivors.
///
/// The default order is deliberately not “newest first”. The thing you just
/// added is rarely the thing you look for next; the thing you open every day
/// is. Pinning is the manual override.
enum BookmarkRanker {
    static func arrange(
        _ bookmarks: [Bookmark],
        query: String,
        sort: BookmarkSort,
        now: Date = Date()
    ) -> [Bookmark] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = FuzzyMatcher.filter(trimmed, in: bookmarks)

        switch sort {
        case .relevance:
            return rankedMatches(matches, query: trimmed, now: now)
        case .name:
            return matches.sorted {
                compareTitles($0.title, $1.title) == .orderedAscending
            }
        case .recentlyAdded:
            // The store keeps the array newest-first; FuzzyMatcher preserves
            // that order, so this is the “just added” view.
            return matches
        }
    }

    /// Convenience for callers that only want the relevance order.
    static func rank(
        _ query: String,
        in bookmarks: [Bookmark],
        now: Date = Date()
    ) -> [Bookmark] {
        arrange(bookmarks, query: query, sort: .relevance, now: now)
    }

    // MARK: - Relevance

    private struct Entry {
        let bookmark: Bookmark
        let index: Int
        let match: Double
        let frecency: Double
    }

    private static func rankedMatches(
        _ bookmarks: [Bookmark],
        query: String,
        now: Date
    ) -> [Bookmark] {
        let entries = bookmarks.enumerated().map { index, bookmark in
            Entry(
                bookmark: bookmark,
                index: index,
                match: query.isEmpty ? 0 : matchScore(bookmark, query: query),
                frecency: frecency(bookmark, now: now)
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.match != rhs.match { return lhs.match > rhs.match }
            if lhs.bookmark.pinned != rhs.bookmark.pinned {
                return lhs.bookmark.pinned
            }
            if lhs.frecency != rhs.frecency { return lhs.frecency > rhs.frecency }

            // Equal relevance: among never-opened bookmarks the stored order is
            // newest-first, so a bookmark just added is not buried under stale
            // ones that were never used either.
            if lhs.index != rhs.index { return lhs.index < rhs.index }

            let titles = compareTitles(lhs.bookmark.title, rhs.bookmark.title)
            if titles != .orderedSame { return titles == .orderedAscending }
            return lhs.bookmark.path < rhs.bookmark.path
        }.map(\.bookmark)
    }

    /// How well a bookmark matches a query in `[0, 1]`. Every query word counts
    /// once; the best field for that word wins. A title hit outranks the same
    /// hit in a description, and a hit in a path outranks neither.
    static func matchScore(_ bookmark: Bookmark, query: String) -> Double {
        let words = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !words.isEmpty else { return 0 }

        let fields: [(value: String, weight: Double)] = [
            (bookmark.title.lowercased(), 1.0),
            (bookmark.description.lowercased(), 0.7),
            (bookmark.path.lowercased(), 0.8)
        ]

        let total = words.reduce(0.0) { sum, word in
            let best = fields.map { field in
                fieldScore(word, in: field.value) * field.weight
            }.max() ?? 0
            return sum + best
        }

        return total / Double(words.count)
    }

    /// `1` for the whole field, then progressively weaker for a prefix, a
    /// word-boundary hit, a plain substring, and a fuzzy approximation.
    private static func fieldScore(_ word: String, in field: String) -> Double {
        guard !field.isEmpty else { return 0 }
        if field == word { return 1.0 }
        if field.hasPrefix(word) { return 0.92 }

        if field.contains(word) {
            let atBoundary = field
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { $0.hasPrefix(word) }
            return atBoundary ? 0.85 : 0.7
        }

        if isSubsequence(word, of: field) { return 0.55 }
        if FuzzyMatcher.ratio(word, field) >= 0.8 { return 0.4 }
        return 0
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let next = iterator.next() {
                if next == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }

    /// A compact version of Mozilla's frecency idea: recent use counts most,
    /// repeated use compounds, but with diminishing returns. It only breaks
    /// ties for a non-empty query and decides the empty-query list.
    static func frecency(_ bookmark: Bookmark, now: Date = Date()) -> Double {
        guard let last = bookmark.lastOpenedAt else { return 0 }

        let age = max(0, now.timeIntervalSince(last))
        let bucket: Double
        switch age {
        case ..<(4 * 3600): bucket = 100
        case ..<(24 * 3600): bucket = 70
        case ..<(7 * 24 * 3600): bucket = 50
        case ..<(30 * 24 * 3600): bucket = 30
        default: bucket = 10
        }

        let useCount = Double(max(bookmark.openCount, 1))
        return bucket * min(3.0, 1 + log2(useCount) * 0.5)
    }

    private static func compareTitles(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }
}
