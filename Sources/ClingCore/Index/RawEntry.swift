import Foundation

/// Minimal record produced by the filesystem walker, consumed by the writer.
public struct RawEntry {
    public let path: String
    public let isDir: Bool
    public init(path: String, isDir: Bool) {
        self.path = path
        self.isDir = isDir
    }
}
