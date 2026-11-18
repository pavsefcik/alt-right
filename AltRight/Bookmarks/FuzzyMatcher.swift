import Foundation

/// Matches bookmark titles, descriptions, and paths using the same rules as the
/// original terminal tool: every query word must match, either as a substring or
/// as a fuzzy token with a similarity ratio of at least 0.8.
enum FuzzyMatcher {
    static func filter(_ query: String, in bookmarks: [Bookmark]) -> [Bookmark] {
        let words = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !words.isEmpty else { return bookmarks }

        return bookmarks.filter { bookmark in
            let haystack = "\(bookmark.title) \(bookmark.description) \(bookmark.path)".lowercased()
            return words.allSatisfy { wordMatches($0, in: haystack) }
        }
    }

    static func wordMatches(_ word: String, in haystack: String) -> Bool {
        if haystack.contains(word) {
            return true
        }

        let tokens = haystack.split(whereSeparator: { $0.isWhitespace })
        return tokens.contains { ratio(word, String($0)) >= 0.8 }
    }

    static func ratio(_ first: String, _ second: String) -> Double {
        let a = Array(first)
        let b = Array(second)
        guard !a.isEmpty || !b.isEmpty else { return 1 }

        let matching = matchingCharacterCount(a, b)
        return (2.0 * Double(matching)) / Double(a.count + b.count)
    }

    /// Ratcliff/Obershelp matching, equivalent to Python's `SequenceMatcher`
    /// ratio for the short strings used here.
    private static func matchingCharacterCount(_ a: [Character], _ b: [Character]) -> Int {
        var ranges: [(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int)] = [
            (0, a.count, 0, b.count)
        ]
        var total = 0

        while let range = ranges.popLast() {
            let match = longestMatch(
                a,
                b,
                aStart: range.aStart,
                aEnd: range.aEnd,
                bStart: range.bStart,
                bEnd: range.bEnd
            )

            guard match.size > 0 else { continue }
            total += match.size

            if range.aStart < match.a {
                ranges.append((range.aStart, match.a, range.bStart, match.b))
            }
            if match.a + match.size < range.aEnd {
                ranges.append((
                    match.a + match.size,
                    range.aEnd,
                    match.b + match.size,
                    range.bEnd
                ))
            }
        }

        return total
    }

    private static func longestMatch(
        _ a: [Character],
        _ b: [Character],
        aStart: Int,
        aEnd: Int,
        bStart: Int,
        bEnd: Int
    ) -> (a: Int, b: Int, size: Int) {
        var bestA = aStart
        var bestB = bStart
        var bestSize = 0

        var positions: [Character: [Int]] = [:]
        if bStart < bEnd {
            for j in bStart..<bEnd {
                positions[b[j], default: []].append(j)
            }
        }

        if aStart < aEnd {
            for i in aStart..<aEnd {
                guard let js = positions[a[i]] else { continue }
                for j in js {
                    var size = 0
                    while i + size < aEnd,
                          j + size < bEnd,
                          a[i + size] == b[j + size] {
                        size += 1
                    }
                    if size > bestSize {
                        bestA = i
                        bestB = j
                        bestSize = size
                    }
                }
            }
        }

        return (bestA, bestB, bestSize)
    }
}
