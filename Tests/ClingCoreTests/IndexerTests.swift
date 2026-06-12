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
}
