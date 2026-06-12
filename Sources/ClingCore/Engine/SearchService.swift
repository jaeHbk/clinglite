import Foundation

/// Thread-safe facade over one or more indexed roots. Each root is a `LiveIndex` (immutable
/// mmap base + in-heap delta) so live filesystem changes are reflected immediately. Searches
/// fan out across all roots and the results are merged, deduped by path, and ranked.
public final class SearchService {
    private let lock = NSLock()
    private var order = [String]()                 // root paths in insertion order
    private var lives = [String: LiveIndex]()      // root path -> live index

    public init() {}

    public var rootPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return order
    }

    /// Add a new root, or replace an existing root's base index with a freshly-built reader.
    public func setRoot(_ root: String, reader: IndexReader) {
        lock.lock(); defer { lock.unlock() }
        if lives[root] == nil { order.append(root) }
        lives[root] = LiveIndex(base: reader)
    }

    public func removeRoot(_ root: String) {
        lock.lock(); defer { lock.unlock() }
        lives[root] = nil
        order.removeAll { $0 == root }
    }

    /// Release resident pages of every root's base index (call when the UI hides).
    public func adviseDontNeedAll() {
        lock.lock(); let all = Array(lives.values); lock.unlock()
        for l in all { l.adviseDontNeed() }
    }

    /// Route a filesystem change to the root whose path is the LONGEST prefix of `path`.
    /// `exists == true` adds/updates the entry; `exists == false` removes it.
    public func applyChange(path: String, exists: Bool, isDir: Bool) {
        let lc = path.lowercased()
        lock.lock()
        var bestRoot: String? = nil
        var bestLen = -1
        for root in order {
            let rlc = root.lowercased()
            if lc == rlc || lc.hasPrefix(rlc.hasSuffix("/") ? rlc : rlc + "/") {
                if rlc.count > bestLen { bestLen = rlc.count; bestRoot = root }
            }
        }
        let live = bestRoot.flatMap { lives[$0] }
        lock.unlock()
        guard let live else { return }
        if exists { live.add(RawEntry(path: path, isDir: isDir)) }
        else { live.remove(path: path) }
    }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        lock.lock(); let all = order.compactMap { lives[$0] }; lock.unlock()
        if all.isEmpty { return [] }

        // Over-fetch per root so the GLOBAL top-`maxResults` survives cross-root merge + dedup.
        // If each root were capped at exactly maxResults, a result that ranks high globally but
        // sits past a single root's cap could be lost; fetching a multiple keeps the merge exact
        // in practice for a launcher's modest maxResults. Dedup is by path (paths are lowercased
        // by the index, so this also collapses case-variant duplicates surfaced by sibling roots).
        let perRoot = all.count > 1 ? maxResults * 2 : maxResults
        var hits = [SearchHit]()
        for live in all { hits.append(contentsOf: live.search(query, maxResults: perRoot)) }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }

        var seen = Set<String>(); var out = [SearchHit]()
        for h in hits where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
