import Foundation

/// Persists one `.idx` per indexed root under a directory (Application Support in the app,
/// a temp dir in tests) plus a small JSON manifest. The index filename is derived
/// deterministically from a stable hash of the root path.
public final class IndexStore {
    public struct ManifestEntry: Codable, Equatable {
        public let root: String
        public let indexFile: String
        public let entryCount: Int
        public let builtAt: Double   // seconds since 1970
    }

    public let directory: URL
    private let manifestURL: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stable (run-independent) djb2 hash — Swift's Hasher is randomized per process and unusable here.
    private func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h, radix: 16)
    }

    public func indexURL(forRoot root: String) -> URL {
        directory.appendingPathComponent("root-\(stableHash(root)).idx")
    }

    /// Open the existing index for `root` if present and valid; otherwise build it.
    public func loadOrBuild(root: String, ignore: IgnoreMatcher) throws -> IndexReader {
        let url = indexURL(forRoot: root)
        if FileManager.default.fileExists(atPath: url.path), let r = try? IndexReader(url: url) {
            return r
        }
        return try reindex(root: root, ignore: ignore)
    }

    /// Always rebuild the index for `root` (atomic), reopen it, and update the manifest.
    public func reindex(root: String, ignore: IgnoreMatcher) throws -> IndexReader {
        let url = indexURL(forRoot: root)
        let n = try Indexer.build(root: root, ignore: ignore, output: url)
        let reader = try IndexReader(url: url)
        updateManifest(ManifestEntry(root: root, indexFile: url.lastPathComponent,
                                     entryCount: n, builtAt: Date().timeIntervalSince1970))
        return reader
    }

    public func manifest() -> [ManifestEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data) else { return [] }
        return entries
    }

    private func updateManifest(_ entry: ManifestEntry) {
        lock.lock(); defer { lock.unlock() }
        var entries = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode([ManifestEntry].self, from: $0)
        } ?? []
        entries.removeAll { $0.root == entry.root }
        entries.append(entry)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: manifestURL, options: .atomic) }
    }
}
