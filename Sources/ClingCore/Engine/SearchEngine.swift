import Foundation

public struct SearchHit: Comparable {
    public let id: Int
    public let path: String
    public let score: Int
    public let isDir: Bool
    public static func < (a: SearchHit, b: SearchHit) -> Bool { a.score > b.score } // higher first
    public static func == (a: SearchHit, b: SearchHit) -> Bool { a.score == b.score && a.path == b.path }
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
        let combined = q.combinedMask
        let hasFuzzy = !q.fuzzyBytes.isEmpty

        // ---- Phase 1: parallel filter -> candidate ids ----
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk = (n + cores - 1) / cores
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
                local.append(i)
                if local.count >= maxCandidates { break }
            }
            store[c] = local
        }
        var cands = [Int](); for c in 0 ..< cores { cands.append(contentsOf: store[c]) }
        if cands.count > maxCandidates { cands.removeLast(cands.count - maxCandidates) }

        // No fuzzy text (ext/folder-only): rank by shallow path, then alpha.
        if !hasFuzzy {
            var hits = cands.map { SearchHit(id: $0, path: r.path($0), score: 0, isDir: IndexFormat.isDir(r.flags[$0])) }
            hits.sort { $0.path.count < $1.path.count }
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

        // Quality gate (top-third) + sort + dedup by path.
        let best = scored.max(by: { $0.score < $1.score })?.score ?? 0
        let minQ = best / 3
        scored = scored.filter { $0.score >= minQ }
        scored.sort()
        var seen = Set<String>(); var out = [SearchHit]()
        for h in scored where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
