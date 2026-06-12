import Foundation

/// Splits a raw query into typed tokens and precomputes letter masks. Mirrors Cling's parser:
/// `.ext`/`*.ext`, `in:<path>`, `depth:<n>`, `seg/`, fuzzy text.
public struct ParsedQuery {
    public let fuzzyTokens: [String]
    public let extTokens: [String]
    public let folderPrefixes: [String]
    public let dirSegments: [String]
    public let depth: Int?

    public let fuzzyBytes: [[UInt8]]     // lowercased, for scoring
    public let extTokenBytes: [[UInt8]]  // lowercased ext strings
    public let combinedMask: UInt64
    public let isEmpty: Bool

    public init(_ raw: String) {
        let lowered = raw.lowercased()
        let toks = lowered.split(separator: " ").map(String.init)

        func isExt(_ t: String) -> Bool { t.hasPrefix(".") || t.hasPrefix("*.") }
        func isIn(_ t: String) -> Bool { t.hasPrefix("in:") && t.count > 3 }
        func isDepth(_ t: String) -> Bool { t.hasPrefix("depth:") && t.count > 6 }
        func isDirSeg(_ t: String) -> Bool { t.hasSuffix("/") && t.count > 1 && !isIn(t) && !isDepth(t) }

        var fz = [String](), ext = [String](), folders = [String](), segs = [String]()
        var d: Int? = nil
        for t in toks {
            if isExt(t) { ext.append(t.hasPrefix("*.") ? String(t.dropFirst(2)) : String(t.dropFirst())) }
            else if isIn(t) { folders.append(String(t.dropFirst(3))) }
            else if isDepth(t) { d = Int(t.dropFirst(6)) }
            else if isDirSeg(t) { segs.append(t) }
            else { fz.append(t) }
        }

        self.fuzzyTokens = fz
        self.extTokens = ext
        self.folderPrefixes = folders
        self.dirSegments = segs
        self.depth = d
        self.fuzzyBytes = fz.map { Array($0.utf8) }
        self.extTokenBytes = ext.map { Array($0.utf8) }

        var m: UInt64 = 0
        for b in fuzzyBytes { m |= b.withUnsafeBufferPointer { letterMaskBytes($0) } }
        for b in extTokenBytes { m |= b.withUnsafeBufferPointer { letterMaskBytes($0) } }
        for s in segs { m |= Array(s.utf8).withUnsafeBufferPointer { letterMaskBytes($0) } }
        self.combinedMask = m

        self.isEmpty = fz.isEmpty && ext.isEmpty && folders.isEmpty && segs.isEmpty
    }
}
