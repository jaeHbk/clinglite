# ClingLite GUI — Plan B1: ClingCore Orchestration Layer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the headless, fully-unit-tested orchestration layer that the GUI (Plan B2) will sit on: a cached-delta `LiveIndex`, fuzzy highlight ranges, a persistent per-root `IndexStore`, and a multi-root `SearchService`.

**Architecture:** Pure Swift additions to the existing `ClingCore` library — no AppKit. Each piece composes the Plan A primitives (`IndexReader`, `IndexWriter`, `Indexer`, `SearchEngine`, `LiveIndex`) and is testable with swift-testing, no GUI required.

**Tech Stack:** Swift 6.3 / SwiftPM, Command Line Tools (no Xcode), swift-testing. Tests run via `./scripts/test.sh [Suite]` (bare suite name auto-promotes to `--filter`; `-c release` requires explicit `--filter`). CLT has NO XCTest — use `import Testing`, `@Suite struct`, `@Test func`, `#expect`, `try #require`.

---

## Context for the implementer

The existing `Sources/ClingCore/Engine/Delta.swift` currently rebuilds a throwaway delta `.idx` and mmaps it on EVERY `search()` call when the delta is non-empty. Task 1 replaces that with a cached delta reader rebuilt only when the delta mutates. The other Plan A APIs are stable and used as-is:

- `IndexReader(url:) throws` → `.count: Int`, `.path(_ i: Int) -> String`, `.adviseDontNeed()`.
- `IndexWriter.write(entries: [RawEntry], to: URL) throws`.
- `RawEntry(path: String, isDir: Bool)`.
- `Indexer.build(root: String, ignore: IgnoreMatcher, output: URL) throws -> Int`.
- `IgnoreMatcher(patterns: [String])` / `IgnoreMatcher(text: String)`.
- `SearchEngine(reader: IndexReader)` → `.search(_ query: String, maxResults: Int) -> [SearchHit]`.
- `SearchHit` (Equatable): `id: Int`, `path: String`, `score: Int`, `isDir: Bool`.
- `ParsedQuery(_ raw: String)` → `.fuzzyBytes: [[UInt8]]` (lowercased token bytes), `.isEmpty: Bool`.
- Index paths are stored LOWERCASED. All search results return lowercased paths.

---

## File Structure

```
Sources/ClingCore/
  Engine/
    Delta.swift          # MODIFY: cached delta reader (rebuild only on mutation)
    Highlight.swift      # CREATE: fuzzyHighlightRanges(query:in:)
    SearchService.swift  # CREATE: multi-root facade (setRoot/search/applyChange/adviseDontNeedAll)
  Index/
    IndexStore.swift     # CREATE: persistent per-root index (loadOrBuild/reindex/manifest)
Tests/ClingCoreTests/
  DeltaTests.swift       # MODIFY: add cached-rebuild tests
  HighlightTests.swift   # CREATE
  IndexStoreTests.swift  # CREATE
  SearchServiceTests.swift # CREATE
```

---

## Task 1: Cached delta reader in LiveIndex

**Files:**
- Modify: `Sources/ClingCore/Engine/Delta.swift` (full replacement)
- Modify: `Tests/ClingCoreTests/DeltaTests.swift` (add tests inside existing `@Suite struct DeltaTests`)

- [ ] **Step 1: Add failing tests** inside the existing `@Suite struct DeltaTests` in `Tests/ClingCoreTests/DeltaTests.swift`:

```swift
    @Test func deltaReaderNotRebuiltWhenUnchanged() throws {
        let r = try reader(["/a/keep.swift"])
        let live = LiveIndex(base: r)
        live.add(RawEntry(path: "/a/new1.swift", isDir: false))
        _ = live.search("swift", maxResults: 10)
        let after1 = live.deltaRebuildCount
        // Searching again WITHOUT mutating the delta must not rebuild the delta index.
        _ = live.search("swift", maxResults: 10)
        _ = live.search("new", maxResults: 10)
        #expect(live.deltaRebuildCount == after1)
        // Mutating the delta marks it dirty; the next search rebuilds exactly once.
        live.add(RawEntry(path: "/a/new2.swift", isDir: false))
        _ = live.search("swift", maxResults: 10)
        #expect(live.deltaRebuildCount == after1 + 1)
    }

    @Test func cachedDeltaStillReturnsCorrectResults() throws {
        let r = try reader(["/a/old.swift", "/a/keep.swift"])
        let live = LiveIndex(base: r)
        live.add(RawEntry(path: "/a/brandnew.swift", isDir: false))
        live.remove(path: "/a/old.swift")
        _ = live.search("swift", maxResults: 10) // warm the cache
        let hits = live.search("swift", maxResults: 10).map { $0.path } // served from cache
        #expect(hits.contains("/a/brandnew.swift"))
        #expect(hits.contains { $0.hasSuffix("keep.swift") })
        #expect(!hits.contains("/a/old.swift"))
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh DeltaTests`
Expected: FAIL — `deltaRebuildCount` is undefined.

- [ ] **Step 3: Replace `Sources/ClingCore/Engine/Delta.swift` entirely** with:

```swift
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
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh DeltaTests`
Expected: all DeltaTests pass (the original `addedFileAppearsAndDeletedDisappears` plus the two new tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/Delta.swift Tests/ClingCoreTests/DeltaTests.swift
git commit -m "perf: cache LiveIndex delta reader (rebuild only on mutation)"
```

---

## Task 2: Fuzzy highlight ranges

**Files:**
- Create: `Sources/ClingCore/Engine/Highlight.swift`
- Create: `Tests/ClingCoreTests/HighlightTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/HighlightTests.swift`:

```swift
import Testing
@testable import ClingCore

@Suite struct HighlightTests {
    @Test func contiguousMatchIsOneRange() {
        // "eng" matches the leading "eng" of "engine.swift" -> a single 0..<3 range.
        let ranges = fuzzyHighlightRanges(query: "eng", in: "engine.swift")
        #expect(ranges == [0 ..< 3])
    }

    @Test func scatteredMatchIsMultipleRanges() {
        // "ei" in "engine": 'e'@0, 'i'@3 -> two single-char ranges.
        let ranges = fuzzyHighlightRanges(query: "ei", in: "engine")
        #expect(ranges == [0 ..< 1, 3 ..< 4])
    }

    @Test func caseInsensitive() {
        let ranges = fuzzyHighlightRanges(query: "ENG", in: "Engine")
        #expect(ranges == [0 ..< 3])
    }

    @Test func noMatchIsEmpty() {
        #expect(fuzzyHighlightRanges(query: "zzz", in: "engine").isEmpty)
    }

    @Test func nonFuzzyTokensIgnored() {
        // Only fuzzy tokens contribute; ".png" is an extension token, not fuzzy text.
        #expect(fuzzyHighlightRanges(query: ".png", in: "engine.png").isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh HighlightTests`
Expected: FAIL — `fuzzyHighlightRanges` undefined.

- [ ] **Step 3: Implement `Sources/ClingCore/Engine/Highlight.swift`**

```swift
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
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh HighlightTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/Highlight.swift Tests/ClingCoreTests/HighlightTests.swift
git commit -m "feat: fuzzy highlight ranges for result display"
```

---

## Task 3: Persistent per-root IndexStore

**Files:**
- Create: `Sources/ClingCore/Index/IndexStore.swift`
- Create: `Tests/ClingCoreTests/IndexStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/IndexStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import ClingCore

@Suite struct IndexStoreTests {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString))")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func makeTree() throws -> URL {
        let root = tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("Readme.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func loadOrBuildThenReopenUsesCache() throws {
        let storeDir = tempDir(); let root = try makeTree()
        let store = IndexStore(directory: storeDir)
        let r1 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r1.count >= 3)
        // The index file now exists; a second loadOrBuild opens the SAME file (no rebuild needed).
        let url = store.indexURL(forRoot: root.path)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let r2 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r2.count == r1.count)
        try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: storeDir)
    }

    @Test func reindexPicksUpNewFilesAndUpdatesManifest() throws {
        let storeDir = tempDir(); let root = try makeTree()
        let store = IndexStore(directory: storeDir)
        let r1 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        let before = r1.count
        try "c".write(to: root.appendingPathComponent("src/Parser.swift"), atomically: true, encoding: .utf8)
        let r2 = try store.reindex(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r2.count > before)
        let entry = store.manifest().first { $0.root == root.path }
        #expect(entry != nil)
        #expect(entry?.entryCount == r2.count)
        try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: storeDir)
    }

    @Test func distinctRootsGetDistinctIndexFiles() {
        let store = IndexStore(directory: tempDir())
        #expect(store.indexURL(forRoot: "/Users/a").lastPathComponent
                != store.indexURL(forRoot: "/Users/b").lastPathComponent)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh IndexStoreTests`
Expected: FAIL — `IndexStore` undefined.

- [ ] **Step 3: Implement `Sources/ClingCore/Index/IndexStore.swift`**

```swift
import Foundation

/// Persists one `.idx` per indexed root under a directory (Application Support in the app,
/// a temp dir in tests) plus a small JSON manifest. The index filename is derived
/// deterministically from a stable hash of the root path.
public final class IndexStore {
    public struct ManifestEntry: Codable, Equatable {
        public let root: String
        public let indexFile: String
        public let entryCount: Int
        public let builtAt: Double   // seconds since 1970
    }

    public let directory: URL
    private let manifestURL: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stable (run-independent) djb2 hash — Swift's Hasher is randomized per process and unusable here.
    private func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h, radix: 16)
    }

    public func indexURL(forRoot root: String) -> URL {
        directory.appendingPathComponent("root-\(stableHash(root)).idx")
    }

    /// Open the existing index for `root` if present and valid; otherwise build it.
    public func loadOrBuild(root: String, ignore: IgnoreMatcher) throws -> IndexReader {
        let url = indexURL(forRoot: root)
        if FileManager.default.fileExists(atPath: url.path), let r = try? IndexReader(url: url) {
            return r
        }
        return try reindex(root: root, ignore: ignore)
    }

    /// Always rebuild the index for `root` (atomic), reopen it, and update the manifest.
    public func reindex(root: String, ignore: IgnoreMatcher) throws -> IndexReader {
        let url = indexURL(forRoot: root)
        let n = try Indexer.build(root: root, ignore: ignore, output: url)
        let reader = try IndexReader(url: url)
        updateManifest(ManifestEntry(root: root, indexFile: url.lastPathComponent,
                                     entryCount: n, builtAt: Date().timeIntervalSince1970))
        return reader
    }

    public func manifest() -> [ManifestEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data) else { return [] }
        return entries
    }

    private func updateManifest(_ entry: ManifestEntry) {
        lock.lock(); defer { lock.unlock() }
        var entries = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode([ManifestEntry].self, from: $0)
        } ?? []
        entries.removeAll { $0.root == entry.root }
        entries.append(entry)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: manifestURL, options: .atomic) }
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh IndexStoreTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Index/IndexStore.swift Tests/ClingCoreTests/IndexStoreTests.swift
git commit -m "feat: persistent per-root index store with manifest"
```

---

## Task 4: Multi-root SearchService

**Files:**
- Create: `Sources/ClingCore/Engine/SearchService.swift`
- Create: `Tests/ClingCoreTests/SearchServiceTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/SearchServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import ClingCore

@Suite struct SearchServiceTests {
    private func reader(_ paths: [String]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        return try IndexReader(url: url)
    }

    @Test func searchMergesAcrossRoots() throws {
        let svc = SearchService()
        svc.setRoot("/projA", reader: try reader(["/projA/engine.swift"]))
        svc.setRoot("/projB", reader: try reader(["/projB/engine_test.swift"]))
        let hits = svc.search("engine", maxResults: 10).map { $0.path }
        #expect(hits.contains("/proja/engine.swift"))
        #expect(hits.contains("/projb/engine_test.swift"))
    }

    @Test func dedupKeepsSinglePathAcrossRoots() throws {
        let svc = SearchService()
        // Two roots that both surface the same path: result must appear once.
        svc.setRoot("/x", reader: try reader(["/shared/engine.swift"]))
        svc.setRoot("/y", reader: try reader(["/shared/engine.swift"]))
        let hits = svc.search("engine", maxResults: 10).map { $0.path }
        #expect(hits.filter { $0 == "/shared/engine.swift" }.count == 1)
    }

    @Test func applyChangeRoutesToLongestPrefixRoot() throws {
        let svc = SearchService()
        svc.setRoot("/home", reader: try reader(["/home/keep.swift"]))
        svc.setRoot("/home/projects", reader: try reader(["/home/projects/old.swift"]))
        // Add a new file under the deeper root; remove one from it.
        svc.applyChange(path: "/home/projects/fresh.swift", exists: true, isDir: false)
        svc.applyChange(path: "/home/projects/old.swift", exists: false, isDir: false)
        let hits = svc.search("swift", maxResults: 10).map { $0.path }
        #expect(hits.contains("/home/projects/fresh.swift"))
        #expect(hits.contains("/home/keep.swift"))
        #expect(!hits.contains("/home/projects/old.swift"))
    }

    @Test func setRootReplacesBase() throws {
        let svc = SearchService()
        svc.setRoot("/r", reader: try reader(["/r/before.swift"]))
        svc.setRoot("/r", reader: try reader(["/r/after.swift"]))  // replace
        let hits = svc.search("swift", maxResults: 10).map { $0.path }
        #expect(hits == ["/r/after.swift"])
        #expect(svc.rootPaths == ["/r"])
    }

    @Test func emptyServiceReturnsNothing() {
        #expect(SearchService().search("x", maxResults: 10).isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh SearchServiceTests`
Expected: FAIL — `SearchService` undefined.

- [ ] **Step 3: Implement `Sources/ClingCore/Engine/SearchService.swift`**

```swift
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

        var hits = [SearchHit]()
        for live in all { hits.append(contentsOf: live.search(query, maxResults: maxResults)) }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }

        var seen = Set<String>(); var out = [SearchHit]()
        for h in hits where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh SearchServiceTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/SearchService.swift Tests/ClingCoreTests/SearchServiceTests.swift
git commit -m "feat: multi-root SearchService (merge, change routing, base swap)"
```

---

## Task 5: Full suite green (debug + release)

**Files:** none (verification)

- [ ] **Step 1: Full debug suite**

Run: `./scripts/test.sh`
Expected: all suites pass (Plan A's 40 tests + the new Delta/Highlight/IndexStore/SearchService tests). Report the "Test run with N tests" line.

- [ ] **Step 2: Full release suite**

Run: `./scripts/test.sh -c release`
Expected: all pass (the 2M-file harness latency assertion is active in release).

- [ ] **Step 3: Commit a status note**

```bash
printf '%s\n' "Plan B1 (ClingCore orchestration) complete: cached-delta LiveIndex, highlight ranges, IndexStore, SearchService — all unit-tested." >> STATUS.md
git add STATUS.md
git commit -m "docs: Plan B1 orchestration layer complete"
```

---

## Self-Review

**Spec coverage (GUI spec §3 orchestration bullets):**
- Cached delta reader → Task 1. ✅
- `SearchService` (multi-root merge, change routing by longest-prefix, base swap, adviseDontNeedAll) → Task 4. ✅
- `IndexStore` (loadOrBuild/reindex/manifest, deterministic per-root file) → Task 3. ✅
- `highlightRanges` → Task 2. ✅
- (`PathReveal`, hotkey, panel, FSEvents, menu bar, settings, build-app are Plan B2 — the GUI target — not B1.)

**Placeholder scan:** No TBD/TODO. Every code step is complete and verbatim.

**Type consistency:** `LiveIndex(base:)` + `.add/.remove/.search/.adviseDontNeed/.deltaRebuildCount`; `fuzzyHighlightRanges(query:in:) -> [Range<Int>]`; `IndexStore(directory:)` + `.indexURL(forRoot:)/.loadOrBuild(root:ignore:)/.reindex(root:ignore:)/.manifest()` + `ManifestEntry{root,indexFile,entryCount,builtAt}`; `SearchService()` + `.setRoot(_:reader:)/.removeRoot(_:)/.rootPaths/.adviseDontNeedAll()/.applyChange(path:exists:isDir:)/.search(_:maxResults:)`. All consistent across tasks and match the Plan A APIs (`IndexReader`, `IndexWriter.write`, `Indexer.build`, `SearchEngine`, `SearchHit`, `RawEntry`, `ParsedQuery.fuzzyBytes`).

**Note on lowercased paths:** tests assert lowercased result paths (e.g. `/proja/engine.swift`) because the index stores lowercased bytes — consistent with Plan A behavior. `SearchService.applyChange` lowercases for prefix routing.
