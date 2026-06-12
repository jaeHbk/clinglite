import Foundation

/// Pure, testable file metadata for the preview pane: kind, human size, modified date.
/// Resolves the lowercased index path to the real on-disk path first (via PathResolver).
public struct FilePreviewInfo: Equatable {
    public let name: String
    public let realPath: String
    public let isDir: Bool
    public let kind: String          // e.g. "swift", "PDF document", "Folder"
    public let sizeText: String      // e.g. "1.2 KB", "—" for dirs/missing
    public let modifiedText: String  // e.g. "2026-06-12 00:06", "—" if unknown

    public init(indexPath: String, isDir: Bool) {
        let real = PathResolver.resolve(indexPath)
        self.realPath = real
        self.name = (real as NSString).lastPathComponent
        self.isDir = isDir

        let fm = FileManager.default
        var attrs: [FileAttributeKey: Any]? = try? fm.attributesOfItem(atPath: real)
        // attributesOfItem follows symlinks; fall back to nil-safe handling.
        if attrs == nil { attrs = nil }

        // Kind
        if isDir {
            self.kind = "Folder"
        } else {
            let ext = (real as NSString).pathExtension
            self.kind = ext.isEmpty ? "Document" : ext.lowercased()
        }

        // Size
        if isDir {
            self.sizeText = "—"
        } else if let size = attrs?[.size] as? NSNumber {
            self.sizeText = FilePreviewInfo.humanSize(size.int64Value)
        } else {
            self.sizeText = "—"
        }

        // Modified
        if let date = attrs?[.modificationDate] as? Date {
            self.modifiedText = FilePreviewInfo.dateText(date)
        } else {
            self.modifiedText = "—"
        }
    }

    /// Test-only direct initializer (no filesystem access).
    init(name: String, realPath: String, isDir: Bool, kind: String, sizeText: String, modifiedText: String) {
        self.name = name; self.realPath = realPath; self.isDir = isDir
        self.kind = kind; self.sizeText = sizeText; self.modifiedText = modifiedText
    }

    public static func humanSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024.0
        var idx = 0
        while value >= 1024.0 && idx < units.count - 1 { value /= 1024.0; idx += 1 }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[idx])
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
