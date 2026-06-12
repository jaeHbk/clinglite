import Foundation

/// Walks `root`, collects RawEntry values, and writes a .idx via IndexWriter. Returns entry count.
public enum Indexer {
    public static func build(root: String, ignore: IgnoreMatcher, output: URL) throws -> Int {
        var entries = [RawEntry]()
        entries.reserveCapacity(1 << 16)
        FileWalker(ignore: ignore).walk(root: root) { entries.append($0) }
        try IndexWriter.write(entries: entries, to: output)
        return entries.count
    }
}
