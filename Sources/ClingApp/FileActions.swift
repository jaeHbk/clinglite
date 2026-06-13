import AppKit
import Quartz

/// Thin wrappers over NSWorkspace / NSPasteboard / QuickLook for acting on a result path.
/// All take the LOWERCASED index path and resolve it to the real on-disk path first.
public enum FileActions {
    public static func open(_ indexPath: String) {
        let real = PathResolver.resolve(indexPath)
        NSWorkspace.shared.open(URL(fileURLWithPath: real))
    }

    public static func revealInFinder(_ indexPath: String) {
        let real = PathResolver.resolve(indexPath)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: real)])
    }

    public static func copyFile(_ indexPath: String) {
        let real = PathResolver.resolve(indexPath)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: real) as NSURL])
    }

    public static func copyPath(_ indexPath: String) {
        let real = PathResolver.resolve(indexPath)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(real, forType: .string)
    }

    /// Open the file's enclosing directory (or the folder itself) in Terminal.app.
    public static func openInTerminal(_ indexPath: String, isDir: Bool) {
        let real = PathResolver.resolve(indexPath)
        let dir = isDir ? real : (real as NSString).deletingLastPathComponent
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        if let termURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([dirURL], withApplicationAt: termURL, configuration: cfg) { _, _ in }
        } else {
            // Fallback: `open -a Terminal <dir>`.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Terminal", dir]
            try? p.run()
        }
    }

    /// Rename the item to `newName` (a basename) within its current directory.
    /// Returns the new REAL path on success, nil on failure (empty/slash name, collision, IO error).
    public static func rename(indexPath: String, to newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        let real = PathResolver.resolve(indexPath)
        let parent = (real as NSString).deletingLastPathComponent
        let dest = (parent as NSString).appendingPathComponent(trimmed)
        let fm = FileManager.default
        guard dest != real else { return real }                 // no-op rename
        guard !fm.fileExists(atPath: dest) else { return nil }   // collision guard
        do { try fm.moveItem(atPath: real, toPath: dest); return dest }
        catch { return nil }
    }
}
