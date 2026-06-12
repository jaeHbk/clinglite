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
                let isDir = info == FTS_D
                // FTS_D = pre-order dir, FTS_F = file, FTS_DP = post-order dir (skip dup), others skip.
                if info == FTS_DP { continue }
                if info != FTS_D && info != FTS_F { continue }

                let path = String(cString: ent.pointee.fts_path)
                let depth = ent.pointee.fts_level
                let name = (path as NSString).lastPathComponent
                if depth > 0, ignore.isIgnored(name: name, isDir: isDir) {
                    if isDir { fts_set(fts, ent, FTS_SKIP) } // prune subtree
                    continue
                }
                if depth > 0 { emit(RawEntry(path: path, isDir: isDir)) }
            }
        }
    }
}
