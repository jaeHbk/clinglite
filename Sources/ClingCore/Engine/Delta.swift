import Foundation

/// Combines an immutable mmap base with an in-heap delta (recent adds) and a tombstone set
/// (deleted/moved base paths). Search results from both are merged, deduped, and re-ranked.
public final class LiveIndex {
    private let base: IndexReader
    private let baseEngine: SearchEngine
    private var deltaEntries = [RawEntry]()
    private var tombstones = Set<String>() // lowercased paths hidden from base
    private let lock = NSLock()

    public init(base: IndexReader) {
        self.base = base
        self.baseEngine = SearchEngine(reader: base)
    }

    public func add(_ e: RawEntry) {
        lock.lock(); defer { lock.unlock() }
        tombstones.remove(e.path.lowercased()) // re-added path is no longer dead
        deltaEntries.append(e)
    }

    public func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        let lc = path.lowercased()
        tombstones.insert(lc)
        deltaEntries.removeAll { $0.path.lowercased() == lc }
    }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        lock.lock()
        let tomb = tombstones
        let delta = deltaEntries
        lock.unlock()

        // Base hits minus tombstones.
        var hits = baseEngine.search(query, maxResults: maxResults * 2).filter { !tomb.contains($0.path) }

        // Delta hits: build a throwaway in-memory reader over just the delta and search it.
        if !delta.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("delta-\(UUID().uuidString).idx")
            defer { try? FileManager.default.removeItem(at: url) }
            if (try? IndexWriter.write(entries: delta, to: url)) != nil,
               let dr = try? IndexReader(url: url) {
                hits.append(contentsOf: SearchEngine(reader: dr).search(query, maxResults: maxResults * 2))
            }
        }

        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }
        var seen = Set<String>(); var out = [SearchHit]()
        for h in hits where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
