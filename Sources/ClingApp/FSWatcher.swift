import Foundation
import ClingCore

/// Watches roots via FSEvents and routes each change to the SearchService (which updates the
/// right root's live delta). Coalesced by the stream; existence is checked per path.
public final class FSWatcher {
    private var stream: FSEventStreamRef?
    private let service: SearchService
    private let roots: [String]

    public init(service: SearchService, roots: [String]) {
        self.service = service
        self.roots = roots
    }

    public func start() {
        guard stream == nil, !roots.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            for i in 0 ..< count {
                let p = String(cString: cPaths[i])
                let exists = FileManager.default.fileExists(atPath: p)
                var isDir: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
                watcher.service.applyChange(path: p, exists: exists, isDir: isDir.boolValue)
            }
        }
        stream = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx,
                                     roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let s = stream {
            FSEventStreamSetDispatchQueue(s, DispatchQueue(label: "clinglite.fsevents", qos: .utility))
            FSEventStreamStart(s)
        }
    }

    public func stop() {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil }
    }
}
