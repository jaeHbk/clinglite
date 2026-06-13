import Testing
import Foundation
@testable import ClingCore

@Suite struct SearchTests {
    private func buildReader(_ paths: [(String, Bool)]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("s-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0.0, isDir: $0.1) }, to: url)
        return try IndexReader(url: url)
    }

    @Test func fuzzyRanksBasenameMatchFirst() throws {
        let r = try buildReader([
            ("/Users/me/Documents/quarterly-report.pdf", false),
            ("/Users/me/repo/tools/rpt.sh", false),
            ("/Users/me/notes/groceries.txt", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search("rpt", maxResults: 10)
        #expect(!hits.isEmpty)
        #expect(hits.first?.path == "/users/me/repo/tools/rpt.sh")
    }

    @Test func extensionFilter() throws {
        let r = try buildReader([
            ("/a/b/image.png", false),
            ("/a/b/doc.pdf", false),
            ("/a/b/photo.png", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search(".png", maxResults: 10)
        #expect(Set(hits.map { $0.path }) == ["/a/b/image.png", "/a/b/photo.png"])
    }

    @Test func folderPrefixFilter() throws {
        let r = try buildReader([
            ("/projects/alpha/main.swift", false),
            ("/projects/beta/main.swift", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search("main in:/projects/alpha", maxResults: 10)
        #expect(hits.map { $0.path } == ["/projects/alpha/main.swift"])
    }

    @Test func emptyQueryReturnsNothing() throws {
        let r = try buildReader([("/a/b.txt", false)])
        #expect(SearchEngine(reader: r).search("", maxResults: 10).isEmpty)
    }

    @Test func dirSegmentFilterRestrictsToMatchingPaths() throws {
        let r = try buildReader([
            ("/Users/me/src/engine.swift", false),
            ("/Users/me/test/engine.swift", false),
            ("/Users/me/src/parser.swift", false),
        ])
        let eng = SearchEngine(reader: r)
        // A bare dir-segment query (no fuzzy text) must keep ONLY paths containing "src/",
        // not dump the whole index.
        let hits = eng.search("src/", maxResults: 10)
        #expect(Set(hits.map { $0.path }) == ["/users/me/src/engine.swift", "/users/me/src/parser.swift"])
    }

    @Test func dirSegmentCombinesWithFuzzy() throws {
        let r = try buildReader([
            ("/Users/me/src/engine.swift", false),
            ("/Users/me/test/engine.swift", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search("engine src/", maxResults: 10)
        #expect(hits.map { $0.path } == ["/users/me/src/engine.swift"])
    }

    @Test func depthFilterRestrictsBySeparatorCount() throws {
        let r = try buildReader([
            ("/a/shallow.txt", false),       // 2 separators
            ("/a/b/c/deep.txt", false),      // 4 separators
        ])
        let eng = SearchEngine(reader: r)
        // depth:2 keeps only paths with <= 2 '/' separators.
        let hits = eng.search(".txt depth:2", maxResults: 10)
        #expect(hits.map { $0.path } == ["/a/shallow.txt"])
    }

    // --- Regression tests for final-review findings ---

    @Test func bestMatchSurvivesLargeBroadResultSet() throws {
        // Build a large index where MANY entries match the query "file", and the single best
        // (exact basename) match is placed LAST. A positional candidate cap would drop it;
        // a score-based top-K must keep it.
        var paths = [(String, Bool)]()
        for i in 0 ..< 60_000 { paths.append(("/bulk/dir\(i)/profile_data_record.txt", false)) }
        paths.append(("/data/file.txt", false)) // the exact, best match — last in index order
        let r = try buildReader(paths)
        let hits = SearchEngine(reader: r).search("file", maxResults: 10)
        #expect(hits.contains { $0.path == "/data/file.txt" })
        // It should also rank at or near the very top (tight basename match).
        #expect(hits.first?.path == "/data/file.txt")
    }

    @Test func unknownExtensionMatchesNothing() throws {
        // A queried extension that doesn't exist in the index must NOT match extension-less
        // files (the 0 = "no extension" sentinel collision bug).
        let r = try buildReader([
            ("/abc_xyz/file", false),     // no extension; letters a,b,c pass the mask
            ("/abc_xyz/note.txt", false),
        ])
        let hits = SearchEngine(reader: r).search(".abcxyz", maxResults: 10)
        #expect(hits.isEmpty)
    }

    @Test func maxResultsZeroReturnsNothing() throws {
        let r = try buildReader([("/a/file.txt", false)])
        #expect(SearchEngine(reader: r).search("file", maxResults: 0).isEmpty)
    }

    @Test func corruptColumnOffsetThrowsInsteadOfCrashing() throws {
        // An index whose path-offset column points past EOF must throw .truncated at open
        // time, never hand out a wild pointer that SIGSEGVs the host process at query time.
        let good = FileManager.default.temporaryDirectory.appendingPathComponent("good-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: [RawEntry(path: "/a/b.txt", isDir: false)], to: good)
        var bytes = try Data(contentsOf: good)
        // offPathOffOff (header field at byte 56) holds the pathOffset column's file offset.
        // Overwrite it with a huge value well past the file end.
        let bogus: UInt64 = 1 << 40
        withUnsafeBytes(of: bogus) { raw in
            for k in 0 ..< 8 { bytes[56 + k] = raw[k] }
        }
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).idx")
        try bytes.write(to: bad)
        #expect(throws: IndexError.self) { _ = try IndexReader(url: bad) }
        try? FileManager.default.removeItem(at: good)
        try? FileManager.default.removeItem(at: bad)
    }

    @Test func exactNameDirRanksAboveEqualScoringFile() throws {
        // The reported bug: searching a folder name surfaced a file instead. With equal fuzzy
        // scores, the FILE used to win on shorter path; the dir+exact-name bonuses must flip this.
        let r = try buildReader([
            ("/root/engine", false),            // FILE, shorter path
            ("/root/deep/sub/engine", true),    // DIR, exact name, deeper path
        ])
        let hits = SearchEngine(reader: r).search("engine", maxResults: 10)
        #expect(hits.first?.path == "/root/deep/sub/engine")  // the folder, not the file
    }

    @Test func dirBonusDoesNotOverrideBetterFuzzyFile() throws {
        // Guard against over-correction: an EXACT-name FILE must still beat a weaker partial-match
        // DIR. Query "eng": file "eng" is an exact basename; dir "engineering" is only a partial.
        let r = try buildReader([
            ("/p/eng", false),            // FILE, exact name "eng"
            ("/p/engineering", true),     // DIR, partial match
        ])
        let hits = SearchEngine(reader: r).search("eng", maxResults: 10)
        #expect(hits.first?.path == "/p/eng")  // exact file wins despite the dir bump
    }
}
