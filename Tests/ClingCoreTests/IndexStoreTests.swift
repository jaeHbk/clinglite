import Testing
import Foundation
@testable import ClingCore

@Suite struct IndexStoreTests {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString))")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func makeTree() throws -> URL {
        let root = tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("Readme.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func loadOrBuildThenReopenUsesCache() throws {
        let storeDir = tempDir(); let root = try makeTree()
        let store = IndexStore(directory: storeDir)
        let r1 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r1.count >= 3)
        // The index file now exists; a second loadOrBuild opens the SAME file (no rebuild needed).
        let url = store.indexURL(forRoot: root.path)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let r2 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r2.count == r1.count)
        try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: storeDir)
    }

    @Test func reindexPicksUpNewFilesAndUpdatesManifest() throws {
        let storeDir = tempDir(); let root = try makeTree()
        let store = IndexStore(directory: storeDir)
        let r1 = try store.loadOrBuild(root: root.path, ignore: IgnoreMatcher(patterns: []))
        let before = r1.count
        try "c".write(to: root.appendingPathComponent("src/Parser.swift"), atomically: true, encoding: .utf8)
        let r2 = try store.reindex(root: root.path, ignore: IgnoreMatcher(patterns: []))
        #expect(r2.count > before)
        let entry = store.manifest().first { $0.root == root.path }
        #expect(entry != nil)
        #expect(entry?.entryCount == r2.count)
        try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: storeDir)
    }

    @Test func distinctRootsGetDistinctIndexFiles() {
        let store = IndexStore(directory: tempDir())
        #expect(store.indexURL(forRoot: "/Users/a").lastPathComponent
                != store.indexURL(forRoot: "/Users/b").lastPathComponent)
    }
}
