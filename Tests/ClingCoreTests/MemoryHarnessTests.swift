import Testing
import Foundation
@testable import ClingCore

@Suite struct MemoryHarnessTests {
    @Test func residentBytesIsPositive() {
        #expect(currentResidentBytes() > 0)
    }

    /// Build a synthetic index of `n` plausible file paths without touching the real FS.
    private func buildSyntheticIndex(_ n: Int) throws -> URL {
        let dirs = ["Users/me/Documents", "Users/me/Code/project/src", "Library/Caches/app",
                    "Users/me/Pictures/2026", "Applications/Tool.app/Contents/Resources"]
        let exts = ["swift", "png", "pdf", "txt", "json", "md", "log", "mp4"]
        var entries = [RawEntry](); entries.reserveCapacity(n)
        for i in 0 ..< n {
            let d = dirs[i % dirs.count]
            let e = exts[i % exts.count]
            entries.append(RawEntry(path: "/\(d)/file_\(i)_report_data.\(e)", isDir: false))
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

        let queries = ["report", "file data", ".png", "src/ swift", "report in:/Users/me/Documents"]
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
}
