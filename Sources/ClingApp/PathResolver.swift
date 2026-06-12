import Foundation

/// Recovers a real on-disk path from the index's lowercased path. macOS default volumes are
/// case-insensitive (so the lowercased path usually opens directly), but file ACTIONS should
/// point at the true-cased path. Strategy: if the path exists as-is, return it; otherwise walk
/// from the deepest existing ancestor, matching each remaining component case-insensitively.
public enum PathResolver {
    public static func resolve(_ lowercasedPath: String) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: lowercasedPath) { return lowercasedPath }

        let comps = lowercasedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = "/"
        for comp in comps {
            let candidate = current == "/" ? "/" + comp : current + "/" + comp
            if fm.fileExists(atPath: candidate) {
                current = candidate
                continue
            }
            // Find a case-insensitive match among the directory's entries.
            let entries = (try? fm.contentsOfDirectory(atPath: current)) ?? []
            if let match = entries.first(where: { $0.lowercased() == comp.lowercased() }) {
                current = current == "/" ? "/" + match : current + "/" + match
            } else {
                // No match at this level — give up and return the original input.
                return lowercasedPath
            }
        }
        return current
    }
}
