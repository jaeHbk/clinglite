import Testing
@testable import ClingApp
@testable import ClingCore

@Suite struct ResultsFormatterTests {
    @Test func splitsNameAndDirAndComputesHighlight() {
        let hits = [SearchHit(id: 0, path: "/users/me/src/engine.swift", score: 100, isDir: false)]
        let rows = ResultsFormatter.rows(from: hits, query: "eng")
        #expect(rows.count == 1)
        #expect(rows[0].name == "engine.swift")
        #expect(rows[0].dir == "/users/me/src")
        #expect(rows[0].path == "/users/me/src/engine.swift")
        #expect(rows[0].isDir == false)
        #expect(rows[0].highlight == [0 ..< 3])      // "eng" of engine
    }

    @Test func rootLevelFileHasEmptyDir() {
        let hits = [SearchHit(id: 1, path: "/readme.md", score: 10, isDir: false)]
        let rows = ResultsFormatter.rows(from: hits, query: "readme")
        #expect(rows[0].name == "readme.md")
        #expect(rows[0].dir == "/")
    }

    @Test func directoryRowFlagged() {
        let hits = [SearchHit(id: 2, path: "/users/me/projects", score: 5, isDir: true)]
        let rows = ResultsFormatter.rows(from: hits, query: "proj")
        #expect(rows[0].isDir == true)
    }
}
