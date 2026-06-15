import Testing
import Foundation
@testable import ClingApp
@testable import ClingCore

/// Repro for "preview correct, list wrong": SearchHit.id is the entry index WITHIN one
/// IndexReader, and merged results come from multiple readers (per-root base + delta), so ids
/// collide. The SwiftUI list keyed on RowModel.id then mis-renders, while the preview (which
/// reads rows[selection] by position) stays correct.
@Suite struct RowIdentityTests {
    private func reader(_ paths: [String]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rid-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        return try IndexReader(url: url)
    }

    @Test func mergedResultsHaveCollidingIdsButUniquePaths() throws {
        // Two readers (mimics base + delta, or two roots). Each gives its first hit id == 0.
        let svc = SearchService()
        svc.setRoot("/a", reader: try reader(["/a/summit-report.pdf"]))
        svc.setRoot("/b", reader: try reader(["/b/summit-notes.txt"]))
        let hits = svc.search("summit", maxResults: 10)
        #expect(hits.count == 2)
        let ids = hits.map { $0.id }
        let paths = hits.map { $0.path }
        // The bug: ids collide across readers...
        #expect(Set(ids).count < ids.count)        // duplicate ids present
        // ...even though paths are unique. Paths are the only safe list identity.
        #expect(Set(paths).count == paths.count)
    }

    @Test func rowIdsCollideAcrossMergedReaders() throws {
        // Concrete repro: 2 readers each return a hit with id 0 -> RowModel.id collides, but
        // RowModel.path stays unique. (Fix will key the list on path, not id.)
        let svc = SearchService()
        svc.setRoot("/a", reader: try reader(["/a/summit-a.pdf", "/a/summit-b.pdf"]))
        svc.setRoot("/b", reader: try reader(["/b/summit-c.pdf", "/b/summit-d.pdf"]))
        let rows = ResultsFormatter.rows(from: svc.search("summit", maxResults: 20), query: "summit")
        #expect(rows.count == 4)
        let ids = rows.map { $0.id }
        let paths = rows.map { $0.path }
        #expect(Set(ids).count < rows.count)     // ids COLLIDE (the bug)
        #expect(Set(paths).count == rows.count)  // paths are unique (the safe identity)
        // The fix: RowModel.identity is unique across the merged set, so the list renders right.
        let identities = rows.map { $0.identity }
        #expect(Set(identities).count == rows.count)
    }
}
