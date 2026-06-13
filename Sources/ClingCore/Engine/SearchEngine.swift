import Foundation

public struct SearchHit: Equatable {
    public let id: Int
    public let path: String
    public let score: Int
    public let isDir: Bool
}

/// Single-pass parallel filter+score over a memory-mapped IndexReader.
public final class SearchEngine {
    private let r: IndexReader
    public init(reader: IndexReader) { self.r = reader }

    /// Lightweight scored record: an entry id plus its rank score. No path String is
    /// materialized here — paths are reconstructed only for the final visible results,
    /// keeping per-query allocation tiny and honoring the structure-of-arrays design.
    private struct Scored { let id: Int; let score: Int }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        if maxResults <= 0 { return [] }
        let q = ParsedQuery(query)
        if q.isEmpty { return [] }
        let n = r.count
        if n == 0 { return [] }

        // Resolve extension tokens to IDs. Real IDs are >= 1; 0 means "no extension" (sentinel)
        // and is ALSO what extID(forExtension:) returns for an unknown extension. So we drop 0s:
        // unknown queried extensions must match nothing (not collide with extension-less files).
        let filterByExt = !q.extTokens.isEmpty
        let extIDset: Set<UInt16> = Set(q.extTokens.map { r.extID(forExtension: $0) }.filter { $0 != 0 })
        if filterByExt && extIDset.isEmpty { return [] } // every queried extension is unknown
        let folderBytes: [[UInt8]] = q.folderPrefixes.map { Array($0.utf8) }
        // Dir-segment tokens ("src/") are matched as literal substrings of the lowercased path
        // (already lowercased by ParsedQuery). Each must appear somewhere in the path.
        let dirSegBytes: [[UInt8]] = q.dirSegments.map { Array($0.utf8) }
        let maxDepth = q.depth   // optional: keep only paths with <= this many '/' separators
        let combined = q.combinedMask
        let hasFuzzy = !q.fuzzyBytes.isEmpty
        let tokens = q.fuzzyBytes

        // Basename-focused prefilter: fuzzy tokens must have all their letters present in the
        // ENTRY'S BASENAME (the bnMasks column), not merely somewhere in the full path. This is
        // the right semantics for a "fuzzy find by name" tool — directory matching is expressed
        // explicitly via `in:` and `seg/` tokens — and it's far more selective than the full-path
        // mask (a short query's letters appear in a huge fraction of long paths but a small
        // fraction of basenames), which keeps scoring work bounded on broad queries.
        var fuzzyMask: UInt64 = 0
        for b in q.fuzzyBytes { b.withUnsafeBufferPointer { fuzzyMask |= letterMaskBytes($0) } }

        // Per-chunk we keep the top-K records BY SCORE (never by index position — a positional
        // cap can drop the best match if it lies past the cap). K is generous so the global
        // top-`maxResults` is guaranteed to survive the merge. Memory is bounded by cores*cap,
        // independent of file count.
        let keep = max(maxResults, 256)
        let cap = keep * 4

        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk = (n + cores - 1) / cores
        let store = UnsafeMutablePointer<[Scored]>.allocate(capacity: cores)
        store.initialize(repeating: [], count: cores)
        defer { store.deinitialize(count: cores); store.deallocate() }

        DispatchQueue.concurrentPerform(iterations: cores) { c in
            let lo = c * chunk, hi = min(lo + chunk, n)
            if lo >= hi { return }
            var local = [Scored](); local.reserveCapacity(min(cap, (hi - lo) / 8 + 1))
            @inline(__always) func trim() {
                if local.count >= cap {
                    local.sort { $0.score > $1.score }
                    local.removeLast(local.count - keep)
                }
            }
            for i in lo ..< hi {
                if r.masks[i] & combined != combined { continue }
                // Fuzzy letters must all be present in the basename (selective, name-focused).
                if hasFuzzy, r.bnMasks[i] & fuzzyMask != fuzzyMask { continue }
                if filterByExt, !extIDset.contains(r.extIDs[i]) { continue }
                if let d = maxDepth, IndexFormat.segCount(r.flags[i]) > d { continue }
                if !folderBytes.isEmpty {
                    let (p, len) = r.pathBytes(i)
                    var ok = false
                    for pre in folderBytes where len >= pre.count {
                        var j = 0; var m = true
                        while j < pre.count { if p[j] != pre[j] { m = false; break }; j += 1 }
                        if m { ok = true; break }
                    }
                    if !ok { continue }
                }
                if !dirSegBytes.isEmpty {
                    let (p, len) = r.pathBytes(i)
                    var allFound = true
                    for seg in dirSegBytes where allFound {
                        if !Self.containsBytes(p, len, seg) { allFound = false }
                    }
                    if !allFound { continue }
                }

                if hasFuzzy {
                    // Score the fuzzy tokens against the BASENAME (all must match; scores summed).
                    // Scoring the short basename rather than the full path is both faster and the
                    // correct "find by name" semantics; bnBoundaries are basename-relative so the
                    // boundary offset is 0.
                    let (p, len) = r.pathBytes(i)
                    let bnOff = Int(r.bnStart[i])
                    let bnPtr = p + bnOff
                    let bnLen = len - bnOff
                    let bnBits = r.bnBoundaries[i]
                    var total = 0
                    var allMatched = true
                    for tok in tokens {
                        let matched: Int? = tok.withUnsafeBufferPointer { tb -> Int? in
                            let txt = UnsafeBufferPointer(start: bnPtr, count: bnLen)
                            return fuzzyScoreBytes(tb, txt, boundaries: bnBits, boundariesOffset: 0)?.score
                        }
                        guard let s = matched else { allMatched = false; break }
                        total += s
                    }
                    if !allMatched { continue }
                    // Rank bonuses (data already in scope). isDir and exact-name matching otherwise
                    // play NO role in scoring, so an equal-scoring FILE with a shorter path would
                    // bury the FOLDER the user searched for. (a) a small directory bump only flips
                    // genuine ties; (b) an exact full-basename match is the strongest "I meant THIS"
                    // signal and wins decisively.
                    if IndexFormat.isDir(r.flags[i]) { total += scoreMatch }
                    if tokens.count == 1 {
                        let tok = tokens[0]
                        if tok.count == bnLen {
                            var exact = true
                            for k in 0 ..< bnLen where bnPtr[k] != tok[k] { exact = false; break }
                            if exact { total += scoreMatch * 4 }
                        }
                    }
                    local.append(Scored(id: i, score: total))
                } else {
                    // No fuzzy text: rank shallow paths first. Use negative byte-length as the
                    // score so the same descending merge keeps the shortest paths.
                    local.append(Scored(id: i, score: -Int(r.pathLen[i])))
                }
                trim()
            }
            // Final per-chunk trim so each slot is <= keep.
            if local.count > keep { local.sort { $0.score > $1.score }; local.removeLast(local.count - keep) }
            store[c] = local
        }

        var merged = [Scored](); for c in 0 ..< cores { merged.append(contentsOf: store[c]) }
        if merged.isEmpty { return [] }

        if hasFuzzy {
            // Quality gate (drop everything below a third of the best score).
            let best = merged.reduce(Int.min) { max($0, $1.score) }
            let minQ = best / 3
            merged = merged.filter { $0.score >= minQ }
        }
        // Sort: fuzzy -> score desc; no-fuzzy -> score is -pathLen so desc = shortest first.
        // Materialize the path String only for the final top results, with an alphabetical
        // tiebreak among equal scores.
        merged.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
        var out = [SearchHit]()
        out.reserveCapacity(min(maxResults, merged.count))
        for s in merged {
            out.append(SearchHit(id: s.id, path: r.path(s.id), score: hasFuzzy ? s.score : 0,
                                 isDir: IndexFormat.isDir(r.flags[s.id])))
            if out.count >= maxResults { break }
        }
        // Stable final ordering with a path tiebreak (paths are unique within one index).
        out.sort { $0.score != $1.score ? $0.score > $1.score
                                        : ($0.path.count != $1.path.count ? $0.path.count < $1.path.count : $0.path < $1.path) }
        return out
    }

    /// True if `needle` appears as a contiguous byte substring of `hay[0..<hayLen]`.
    /// Uses simdFindByte to locate candidate starts on the first byte, then verifies the rest.
    @inline(__always)
    private static func containsBytes(_ hay: UnsafePointer<UInt8>, _ hayLen: Int, _ needle: [UInt8]) -> Bool {
        let m = needle.count
        if m == 0 { return true }
        if m > hayLen { return false }
        let first = needle[0]
        var from = 0
        while true {
            let at = simdFindByte(hay, count: hayLen, needle: first, from: from)
            if at < 0 || at + m > hayLen { return false }
            var j = 1; var ok = true
            while j < m { if hay[at + j] != needle[j] { ok = false; break }; j += 1 }
            if ok { return true }
            from = at + 1
        }
    }
}
