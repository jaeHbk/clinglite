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
}
