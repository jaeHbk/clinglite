import Testing
import Foundation
@testable import ClingCore

@Suite struct MemoryHarnessTests {
    @Test func residentBytesIsPositive() {
        #expect(currentResidentBytes() > 0)
    }

    /// Build a synthetic index of `n` realistically-VARIED file paths without touching the
    /// real FS. Varied basenames matter: a real filesystem has diverse names, so a typical
    /// query's mask prefilter is selective and only a small fraction of entries reach the
    /// scorer. (Uniform names like "file_N_report" would make every query match 100% of
    /// entries — an unrealistic worst case exercised separately in
    /// `pathologicalAllMatchQueryStaysBounded`.)
    private func buildSyntheticIndex(_ n: Int) throws -> URL {
        let dirs = ["Users/me/Documents", "Users/me/Code/project/src", "Library/Caches/app",
                    "Users/me/Pictures/2026", "Applications/Tool.app/Contents/Resources"]
        let exts = ["swift", "png", "pdf", "txt", "json", "md", "log", "mp4"]
        // A pool of varied word stems combined pseudo-randomly per entry (index-derived, so
        // the build stays deterministic without Date/Random, which are unavailable here).
        let words = ["report", "invoice", "summary", "config", "engine", "parser", "render",
                     "module", "vector", "buffer", "session", "account", "profile", "archive",
                     "backup", "cache", "thumbnail", "snapshot", "manifest", "checkout", "widget",
                     "ledger", "receipt", "draft", "final", "review", "export", "import"]
        var entries = [RawEntry](); entries.reserveCapacity(n)
        for i in 0 ..< n {
            let d = dirs[i % dirs.count]
            let e = exts[i % exts.count]
            let w1 = words[i % words.count]
            let w2 = words[(i / words.count + 7) % words.count]
            entries.append(RawEntry(path: "/\(d)/\(w1)_\(w2)_\(i).\(e)", isDir: false))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(n).idx")
        try? FileManager.default.removeItem(at: url)
        try IndexWriter.write(entries: entries, to: url)
        return url
    }

    @Test func memoryCeilingAndLatencyAt2MFiles() throws {
        let n = 2_000_000
        let url = try buildSyntheticIndex(n)
        defer { try? FileManager.default.removeItem(at: url) }

        let before = currentResidentBytes()
        let reader = try IndexReader(url: url)
        let engine = SearchEngine(reader: reader)
        #expect(reader.count == n)

        // Representative real-world queries: each is selective (matches a fraction of entries),
        // as on a real filesystem — this measures the common-case interactive hot path.
        let queries = ["engine", "invoice summary", ".png", "src/ parser", "report in:/Users/me/Documents"]
        var totalMs = 0.0
        for q in queries {
            let t0 = Date()
            let hits = engine.search(q, maxResults: 200)
            totalMs += Date().timeIntervalSince(t0) * 1000
            #expect(hits.count <= 200)
        }

        let after = currentResidentBytes()
        let totalMB = Double(after) / 1_048_576.0
        let deltaMB = Double(after - before) / 1_048_576.0
        let avgMs = totalMs / Double(queries.count)
        print("[harness] n=\(n) idxSize=\(reader.byteCount / 1_048_576)MB totalResident=\(Int(totalMB))MB residentDelta=\(Int(deltaMB))MB avgSearch=\(String(format: "%.1f", avgMs))ms")

        // HARD CEILING (the project's <500MB goal): the ABSOLUTE process footprint while
        // searching a 2M-file index must stay well under 500MB. We assert on absolute
        // footprint, not the before/after delta — phys_footprint is non-monotonic (page
        // eviction/compression between samples can make a delta read negative), so an
        // absolute ceiling is the meaningful, robust proof.
        #expect(totalMB < 450.0)

        // SPEED: representative searches must be interactive. This holds in optimized
        // builds (~65ms for 2M files); a debug build is ~10x slower, so the latency
        // assertion is gated to release. Run `./scripts/test.sh -c release` to exercise it.
        #if !DEBUG
        #expect(avgMs < 150.0)
        #endif
    }

    /// Worst case: a query whose letters are all present in EVERY basename, so the prefilter is
    /// useless and the scorer must run on the full index. Slow by nature (no longer sub-100ms),
    /// but it must stay CORRECT and bounded — never crash, return a bounded top-ranked set, and
    /// add only a modest amount of memory above the index itself.
    ///
    /// This asserts on the test's OWN incremental footprint (max(0, after-before)), not the
    /// absolute process footprint: tests share one process, and a prior test's 2M-entry mapping
    /// can leave ~hundreds of MB of resident pages around, which would make an absolute reading
    /// here reflect the other test rather than this one.
    @Test func pathologicalAllMatchQueryStaysBounded() throws {
        // 800k entries whose basenames all start with "report" → a "report" query matches all.
        let n = 800_000
        var entries = [RawEntry](); entries.reserveCapacity(n)
        for i in 0 ..< n { entries.append(RawEntry(path: "/data/dir\(i % 500)/report_\(i).txt", isDir: false)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("path-\(UUID().uuidString).idx")
        defer { try? FileManager.default.removeItem(at: url) }
        try IndexWriter.write(entries: entries, to: url)

        let before = currentResidentBytes()
        let reader = try IndexReader(url: url)
        let hits = SearchEngine(reader: reader).search("report", maxResults: 200)
        let addedMB = max(0.0, Double(currentResidentBytes() - before) / 1_048_576.0)
        print("[harness-worst] n=\(n) allMatch addedMB=\(Int(addedMB))MB hits=\(hits.count)")

        #expect(hits.count == 200)        // bounded result set even when everything matches
        #expect(addedMB < 250.0)          // this search adds well under the ceiling on top of base
    }
}
