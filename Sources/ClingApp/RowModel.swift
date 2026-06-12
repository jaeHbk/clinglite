import Foundation

/// A presentation-ready search result row. Plain value type (no AppKit) so it's testable.
public struct RowModel: Identifiable, Equatable {
    public let id: Int
    public let name: String           // basename
    public let dir: String            // parent directory (or "/")
    public let path: String           // full (lowercased index) path
    public let isDir: Bool
    public let highlight: [Range<Int>] // byte ranges into `name` to bold
}
