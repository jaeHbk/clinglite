import Foundation

public struct SearchHit: Equatable {
    public let id: Int
    public let path: String
    public let score: Int
    public let isDir: Bool
}

/// Two-phase search over a memory-mapped IndexReader.
public final class SearchEngine {
    private let r: IndexReader
    private let maxCandidates = 50_000
    public init(reader: IndexReader) { self.r = reader }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        let q = ParsedQuery(query)
        if q.isEmpty { return [] }
        let n = r.count
        if n == 0 { return [] }

        // Resolve extension tokens to IDs (0 = unknown -> nothing matches).
        let extIDset: Set<UInt16> = Set(q.extTokens.map { r.extID(forExtension: $0) })
        let filterByExt = !q.extTokens.isEmpty
        let folderBytes: [[UInt8]] = q.folderPrefixes.map { Array($0.utf8) }
        // Dir-segment tokens ("src/") are matched as literal substrings of the lowercased path
        // (already lowercased by ParsedQuery). Each must appear somewhere in the path.
        let dirSegBytes: [[UInt8]] = q.dirSegments.map { Array($0.utf8) }
        let maxDepth = q.depth   // optional: keep only paths with <= this many '/' separators
        let combined = q.combinedMask
        let hasFuzzy = !q.fuzzyBytes.isEmpty

        // ---- Phase 1: parallel filter -> candidate ids ----
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk = (n + cores - 1) / cores
        // Cap per chunk so the merged candidate pool never exceeds maxCandidates overall.
        let perChunkCap = max(maxCandidates / cores, 1)
        let store = UnsafeMutablePointer<[Int]>.allocate(capacity: cores)
        store.initialize(repeating: [], count: cores)
        defer { store.deinitialize(count: cores); store.deallocate() }

        DispatchQueue.concurrentPerform(iterations: cores) { c in
            let lo = c * chunk, hi = min(lo + chunk, n)
            if lo >= hi { return }
            var local = [Int](); local.reserveCapacity((hi - lo) / 8)
            for i in lo ..< hi {
                if r.masks[i] & combined != combined { continue }
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
                local.append(i)
                if local.count >= perChunkCap { break }
            }
            store[c] = local
        }
        var cands = [Int](); for c in 0 ..< cores { cands.append(contentsOf: store[c]) }
        if cands.count > maxCandidates { cands.removeLast(cands.count - maxCandidates) }

        // No fuzzy text (ext/folder/dir-seg/depth-only): rank by shallow path, then alphabetically.
        if !hasFuzzy {
            var hits = cands.map { SearchHit(id: $0, path: r.path($0), score: 0, isDir: IndexFormat.isDir(r.flags[$0])) }
            hits.sort { $0.path.count != $1.path.count ? $0.path.count < $1.path.count : $0.path < $1.path }
            return Array(hits.prefix(maxResults))
        }

        // ---- Phase 2: parallel score ----
        let nc = cands.count
        if nc == 0 { return [] }
        let scoreChunk = max(nc / cores, 512)
        let nChunks = (nc + scoreChunk - 1) / scoreChunk
        let scoreStore = UnsafeMutablePointer<[SearchHit]>.allocate(capacity: nChunks)
        scoreStore.initialize(repeating: [], count: nChunks)
        defer { scoreStore.deinitialize(count: nChunks); scoreStore.deallocate() }

        let tokens = q.fuzzyBytes
        DispatchQueue.concurrentPerform(iterations: nChunks) { ch in
            let lo = ch * scoreChunk, hi = min(lo + scoreChunk, nc)
            if lo >= hi { return }
            var local = [SearchHit](); local.reserveCapacity(hi - lo)
            for idx in lo ..< hi {
                let i = cands[idx]
                let (p, len) = r.pathBytes(i)
                let bnOff = Int(r.bnStart[i])
                let bnBits = r.bnBoundaries[i]
                var total = 0
                var allMatched = true
                for tok in tokens {
                    let matched: Int? = tok.withUnsafeBufferPointer { tb -> Int? in
                        let txt = UnsafeBufferPointer(start: p, count: len)
                        return fuzzyScoreBytes(tb, txt, boundaries: bnBits, boundariesOffset: bnOff)?.score
                    }
                    guard let s = matched else { allMatched = false; break }
                    total += s
                }
                if allMatched {
                    local.append(SearchHit(id: i, path: r.path(i), score: total, isDir: IndexFormat.isDir(r.flags[i])))
                }
            }
            scoreStore[ch] = local
        }

        var scored = [SearchHit](); for c in 0 ..< nChunks { scored.append(contentsOf: scoreStore[c]) }
        if scored.isEmpty { return [] }

        // Quality gate (top-third) + sort (highest score first) + dedup by path.
        let best = scored.max(by: { $0.score < $1.score })?.score ?? 0
        let minQ = best / 3
        scored = scored.filter { $0.score >= minQ }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }
        var seen = Set<String>(); var out = [SearchHit]()
        for h in scored where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
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
