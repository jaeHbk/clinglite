import Foundation

/// Minimal gitignore-style matcher: literal names, `*.ext` suffix globs, and `dir/` (dir-only).
/// Matches against a single path component (the entry's basename) at walk time.
public struct IgnoreMatcher {
    private var literals = Set<String>()
    private var dirLiterals = Set<String>()
    private var suffixes = [String]() // from "*.ext" -> ".ext"

    public init(patterns: [String]) {
        for raw in patterns {
            let p = raw.trimmingCharacters(in: .whitespaces)
            if p.isEmpty || p.hasPrefix("#") { continue }
            if p.hasSuffix("/") { dirLiterals.insert(String(p.dropLast())); continue }
            if p.hasPrefix("*.") { suffixes.append(String(p.dropFirst())); continue }
            literals.insert(p)
        }
    }

    public init(text: String) { self.init(patterns: text.split(separator: "\n").map(String.init)) }

    public func isIgnored(name: String, isDir: Bool) -> Bool {
        if literals.contains(name) { return true }
        if isDir, dirLiterals.contains(name) { return true }
        for s in suffixes where name.hasSuffix(s) { return true }
        return false
    }

    public var isEmpty: Bool { literals.isEmpty && dirLiterals.isEmpty && suffixes.isEmpty }
}
