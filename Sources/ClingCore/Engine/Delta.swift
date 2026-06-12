import Foundation

/// Combines an immutable mmap base with an in-heap delta (recent adds) and a tombstone set
/// (deleted/moved base paths). The delta is materialized into its own mmap'd index that is
/// rebuilt ONLY when the delta mutates (not on every search), so interactive typing over a
/// busy filesystem stays cheap.
public final class LiveIndex {
    private let base: IndexReader
    private let baseEngine: SearchEngine
    private var deltaEntries = [RawEntry]()
    private var tombstones = Set<String>()   // lowercased paths hidden from base
    private let lock = NSLock()

    // Cached delta index (rebuilt lazily when `deltaDirty`).
    // `deltaReader` is retained only to keep the mmap alive for the lifetime of the cache;
    // it is also held transitively by `deltaEngine` (which owns its reader), so it's never
    // read directly — do not "remove unused" it.
    private var deltaReader: IndexReader?
    private var deltaEngine: SearchEngine?
    private var deltaURL: URL?
    private var deltaDirty = false

    /// Number of times the delta index has been (re)built. For tests/diagnostics.
    public private(set) var deltaRebuildCount = 0

    public init(base: IndexReader) {
        self.base = base
        self.baseEngine = SearchEngine(reader: base)
    }

    deinit { if let u = deltaURL { try? FileManager.default.removeItem(at: u) } }

    public func add(_ e: RawEntry) {
        lock.lock(); defer { lock.unlock() }
        tombstones.remove(e.path.lowercased())
        deltaEntries.append(e)
        deltaDirty = true
    }

    public func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        let lc = path.lowercased()
        tombstones.insert(lc)
        deltaEntries.removeAll { $0.path.lowercased() == lc }
        deltaDirty = true
    }

    /// Release resident pages of the base index (called when the app backgrounds).
    public func adviseDontNeed() { base.adviseDontNeed() }

    /// Rebuild the cached delta index from the current `deltaEntries`. Caller must hold `lock`.
    private func rebuildDeltaLocked() {
        deltaEngine = nil
        deltaReader = nil
        if let u = deltaURL { try? FileManager.default.removeItem(at: u); deltaURL = nil }
        deltaRebuildCount += 1
        guard !deltaEntries.isEmpty else { return }
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("clinglite-delta-\(UUID().uuidString).idx")
        guard (try? IndexWriter.write(entries: deltaEntries, to: u)) != nil,
              let dr = try? IndexReader(url: u) else { return }
        deltaURL = u
        deltaReader = dr
        deltaEngine = SearchEngine(reader: dr)
    }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        lock.lock()
        if deltaDirty { rebuildDeltaLocked(); deltaDirty = false }
        let tomb = tombstones
        let de = deltaEngine
        lock.unlock()

        var hits = baseEngine.search(query, maxResults: maxResults * 2).filter { !tomb.contains($0.path) }
        if let de { hits.append(contentsOf: de.search(query, maxResults: maxResults * 2)) }

        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }
        var seen = Set<String>(); var out = [SearchHit]()
        for h in hits where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
