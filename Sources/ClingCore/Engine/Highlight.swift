import Foundation

/// Byte-offset ranges (into the basename's lowercased UTF-8) of characters matched by the
/// fuzzy tokens of `query`. Uses a leftmost greedy subsequence match per token — approximate
/// vs the scorer's best alignment, but stable and good enough for display bolding. Returns
/// coalesced contiguous ranges, sorted ascending. Extension/folder/dir-segment/depth tokens
/// do not contribute (only `ParsedQuery.fuzzyBytes`).
public func fuzzyHighlightRanges(query: String, in basename: String) -> [Range<Int>] {
    let pq = ParsedQuery(query)
    if pq.fuzzyBytes.isEmpty { return [] }
    let hay = Array(basename.lowercased().utf8)
    if hay.isEmpty { return [] }
    var marked = [Bool](repeating: false, count: hay.count)

    for tok in pq.fuzzyBytes where !tok.isEmpty {
        var ti = 0
        var hi = 0
        while hi < hay.count && ti < tok.count {
            if hay[hi] == tok[ti] { marked[hi] = true; ti += 1 }
            hi += 1
        }
    }

    var ranges = [Range<Int>]()
    var i = 0
    while i < marked.count {
        if marked[i] {
            var j = i + 1
            while j < marked.count && marked[j] { j += 1 }
            ranges.append(i ..< j)
            i = j
        } else {
            i += 1
        }
    }
    return ranges
}
