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
}
