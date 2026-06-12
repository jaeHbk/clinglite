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
