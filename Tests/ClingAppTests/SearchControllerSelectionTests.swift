import Testing
import Foundation
@testable import ClingApp
@testable import ClingCore

@Suite struct SearchControllerSelectionTests {
    private func service(_ paths: [String]) throws -> SearchService {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scsel-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        let svc = SearchService()
        svc.setRoot("/", reader: try IndexReader(url: url))
        return svc
    }

    private func waitForRows(_ c: SearchController) async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    @MainActor
    @Test func newQueryResetsSelectionToTop() async throws {
        // The bug: after arrowing down then typing more (changing the result set), selection
        // stayed clamped to the old index, so the previewed row != the top/expected match.
        let svc = try service([
            "/d/report-alpha.txt", "/d/report-beta.txt", "/d/report-gamma.txt",
            "/d/report-q1.txt", "/d/report-q2.txt",
        ])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "report"
        try await waitForRows(c)
        #expect(c.rows.count >= 5)
        c.moveSelection(4)                       // arrow down to a non-top row
        #expect(c.selection == 4)
        c.query = "report-q"                     // NEW query -> different result set
        try await waitForRows(c)
        // After a new query, the selection must reset to the top so preview matches the result.
        #expect(c.selection == 0)
        #expect(c.selectedRow?.name == c.rows.first?.name)
    }

    @MainActor
    @Test func selectedRowAlwaysMatchesAVisibleRow() async throws {
        let svc = try service(["/d/engine.txt", "/d/engineer.txt", "/d/engine-x.txt"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "engine"
        try await waitForRows(c)
        c.moveSelection(2)
        c.query = "engineer"                     // narrows to 1
        try await waitForRows(c)
        #expect(c.selection == 0)
        #expect(c.selectedRow != nil)            // never nil/stale after a query change
        #expect(c.selectedRow?.name == c.rows.first?.name)
    }

    @MainActor
    @Test func arrowNavigationStillWorksWithinAQuery() async throws {
        // The reset must NOT break arrow nav within the same result set.
        let svc = try service(["/d/note-a.txt", "/d/note-b.txt", "/d/note-c.txt"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "note"
        try await waitForRows(c)
        c.moveSelection(1)
        #expect(c.selection == 1)                // arrow still moves selection within the query
        c.moveSelection(1)
        #expect(c.selection == 2)
    }
}
