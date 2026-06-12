import Testing
import Foundation
@testable import ClingApp
@testable import ClingCore

@Suite struct SearchControllerTests {
    private func service(_ paths: [String]) throws -> SearchService {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        let svc = SearchService()
        svc.setRoot("/", reader: try IndexReader(url: url))
        return svc
    }

    @MainActor
    @Test func searchProducesRowsAfterDebounce() async throws {
        let svc = try service(["/users/me/engine.swift", "/users/me/readme.md"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "engine"
        // Wait for debounce + async search to publish.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(c.rows.contains { $0.name == "engine.swift" })
        #expect(!c.rows.contains { $0.name == "readme.md" })
    }

    @MainActor
    @Test func emptyQueryClearsRows() async throws {
        let svc = try service(["/users/me/engine.swift"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "engine"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!c.rows.isEmpty)
        c.query = ""
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(c.rows.isEmpty)
        #expect(c.selection == 0)
    }
}
