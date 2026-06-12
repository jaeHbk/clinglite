import Foundation
import ClingCore

/// Converts engine `SearchHit`s into display `RowModel`s: splits basename/dir and computes
/// highlight ranges for the basename. Pure — unit tested without a GUI.
public enum ResultsFormatter {
    public static func rows(from hits: [SearchHit], query: String) -> [RowModel] {
        hits.map { hit in
            let path = hit.path
            let name: String
            let dir: String
            if let slash = path.utf8.lastIndex(of: 0x2F) {
                let nameStart = path.utf8.index(after: slash)
                name = String(decoding: path.utf8[nameStart...], as: UTF8.self)
                let dirBytes = path.utf8[..<slash]
                dir = dirBytes.isEmpty ? "/" : String(decoding: dirBytes, as: UTF8.self)
            } else {
                name = path
                dir = ""
            }
            return RowModel(id: hit.id, name: name, dir: dir, path: path, isDir: hit.isDir,
                            highlight: fuzzyHighlightRanges(query: query, in: name))
        }
    }
}
