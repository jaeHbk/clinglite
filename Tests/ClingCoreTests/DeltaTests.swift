import Testing
import Foundation
@testable import ClingCore

@Suite struct DeltaTests {
    private func reader(_ paths: [String]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("d-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        return try IndexReader(url: url)
    }

    @Test func addedFileAppearsAndDeletedDisappears() throws {
        let r = try reader(["/a/old.swift", "/a/keep.swift"])
        let live = LiveIndex(base: r)
        live.add(RawEntry(path: "/a/brandnew.swift", isDir: false))
        live.remove(path: "/a/old.swift")

        let hits = live.search("swift", maxResults: 10).map { $0.path }
        #expect(hits.contains("/a/brandnew.swift"))   // delta add visible
        #expect(hits.contains { $0.hasSuffix("keep.swift") })
        #expect(!hits.contains("/a/old.swift"))       // tombstoned base entry hidden
    }
}
