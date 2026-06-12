import AppKit
import QuickLookThumbnailing

/// Loads a downsampled QuickLook thumbnail for a file, falling back to its Finder icon.
/// Bounded NSCache keeps memory flat; thumbnails are generated off the main thread.
@MainActor
final class ThumbnailLoader: ObservableObject {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()
    private let side: CGFloat = 256   // generation size; displayed smaller

    init() { cache.countLimit = 256 }

    /// Synchronous Finder icon (always available, cheap) for immediate display.
    func icon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    /// Async high-quality thumbnail; calls `completion` on the main actor when ready.
    func thumbnail(for path: String, completion: @escaping (NSImage) -> Void) {
        if let cached = cache.object(forKey: path as NSString) { completion(cached); return }
        let url = URL(fileURLWithPath: path)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let rep else { return }
            let image = rep.nsImage
            Task { @MainActor in
                self.cache.setObject(image, forKey: path as NSString)  // rebuild key on main actor
                completion(image)
            }
        }
    }
}
