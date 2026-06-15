import Foundation

/// A presentation-ready search result row. Plain value type (no AppKit) so it's testable.
public struct RowModel: Identifiable, Equatable {
    public let id: Int                 // entry index WITHIN one IndexReader — NOT unique across a merge
    public let name: String           // basename
    public let dir: String            // parent directory (or "/")
    public let path: String           // full (lowercased index) path — unique across the merged result set
    public let isDir: Bool
    public let highlight: [Range<Int>] // byte ranges into `name` to bold

    /// Stable, collision-free list identity. `id` is only unique within a single IndexReader;
    /// merged results (per-root base + delta, or multiple roots) reuse ids across readers, which
    /// makes a list keyed on `id` mis-render. `path` is dedup'd unique across the whole result
    /// set, so it is the correct SwiftUI ForEach identity.
    public var identity: String { path }
}
