import Foundation

/// Fast recursive filesystem walk via fts(3). Emits a RawEntry per file and directory,
/// skipping entries (and pruning directories) that the ignore matcher rejects.
public final class FileWalker {
    private let ignore: IgnoreMatcher
    public init(ignore: IgnoreMatcher) { self.ignore = ignore }

    public func walk(root: String, _ emit: (RawEntry) -> Void) {
        root.withCString { c0 in
            let paths: [UnsafeMutablePointer<CChar>?] = [strdup(c0), nil]
            let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: paths.count)
            argv.initialize(from: paths, count: paths.count)
            defer { free(paths[0]); argv.deallocate() }

            guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
            defer { fts_close(fts) }

            while let ent = fts_read(fts) {
                let info = Int32(ent.pointee.fts_info)
                // FTS_D = pre-order dir, FTS_F = file, FTS_DP = post-order dir (skip dup), others skip.
                if info == FTS_DP { continue }
                if info != FTS_D && info != FTS_F { continue }
                let isDir = info == FTS_D

                let path = String(cString: ent.pointee.fts_path)
                let depth = ent.pointee.fts_level
                if depth > 0, ignore.isIgnored(name: Self.basename(path), isDir: isDir) {
                    if isDir { fts_set(fts, ent, FTS_SKIP) } // prune subtree
                    continue
                }
                if depth > 0 { emit(RawEntry(path: path, isDir: isDir)) }
            }
        }
    }

    /// Last path component, computed over the UTF-8 view to avoid the NSString bridge on the
    /// per-entry hot path. Returns the whole string if there is no '/'.
    @inline(__always)
    private static func basename(_ path: String) -> String {
        let u = path.utf8
        guard let lastSlash = u.lastIndex(of: 0x2F) else { return path }
        return String(decoding: u[u.index(after: lastSlash)...], as: UTF8.self)
    }
}
