import Testing
import Foundation
@testable import ClingCore

@Suite struct IndexerTests {
    @Test func ignoreMatcher() {
        let m = IgnoreMatcher(patterns: [".DS_Store", "*.log", "node_modules/", ".git/"])
        #expect(m.isIgnored(name: ".DS_Store", isDir: false))
        #expect(m.isIgnored(name: "debug.log", isDir: false))
        #expect(m.isIgnored(name: "node_modules", isDir: true))
        #expect(m.isIgnored(name: ".git", isDir: true))
        #expect(!m.isIgnored(name: "main.swift", isDir: false))
        #expect(!m.isIgnored(name: "node_modules", isDir: false)) // dir-only pattern
    }

    @Test func commentsAndBlank() {
        let m = IgnoreMatcher(text: "# comment\n\n*.tmp\n")
        #expect(m.isIgnored(name: "a.tmp", isDir: false))
    }

    @Test func walkerEnumeratesTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("walk-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "y".write(to: root.appendingPathComponent("sub/b.swift"), atomically: true, encoding: .utf8)
        try "z".write(to: root.appendingPathComponent("ignore.log"), atomically: true, encoding: .utf8)

        var found = [String]()
        let walker = FileWalker(ignore: IgnoreMatcher(patterns: ["*.log"]))
        walker.walk(root: root.path) { entry in found.append(entry.path) }

        #expect(found.contains { $0.hasSuffix("/a.txt") })
        #expect(found.contains { $0.hasSuffix("/sub/b.swift") })
        #expect(!found.contains { $0.hasSuffix("ignore.log") })
        try? fm.removeItem(at: root)
    }

    @Test func indexerEndToEnd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("idx-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let idx = root.appendingPathComponent("out.idx")
        let count = try Indexer.build(root: root.path, ignore: IgnoreMatcher(patterns: []), output: idx)
        #expect(count >= 3) // src, Engine.swift, README.md

        let r = try IndexReader(url: idx)
        let hits = SearchEngine(reader: r).search("engine", maxResults: 10)
        #expect(hits.contains { $0.path.hasSuffix("/src/engine.swift") })
        try? fm.removeItem(at: root)
    }
}
