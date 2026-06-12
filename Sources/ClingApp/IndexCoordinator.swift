import Foundation
import ClingCore

/// Owns the IndexStore + SearchService. On launch, loads (or builds) an index per configured
/// root so search works immediately, then can reindex in the background. Thread-safe-ish via a
/// serial queue for index mutations.
public final class IndexCoordinator {
    public let service = SearchService()
    private let store: IndexStore
    private let ignore: IgnoreMatcher
    private let queue = DispatchQueue(label: "clinglite.index", qos: .utility)

    public init(storeDirectory: URL, ignorePatterns: [String]) {
        self.store = IndexStore(directory: storeDirectory)
        self.ignore = IgnoreMatcher(patterns: ignorePatterns)
    }

    /// Synchronously load existing indexes (fast: just mmaps) so the UI is usable immediately.
    public func loadExisting(roots: [String]) {
        for root in roots {
            if let reader = try? store.loadOrBuild(root: root, ignore: ignore) {
                service.setRoot(root, reader: reader)
            }
        }
    }

    /// Background full reindex of one root, swapping the fresh base into the service.
    public func reindex(root: String, completion: ((Int) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            if let reader = try? self.store.reindex(root: root, ignore: self.ignore) {
                self.service.setRoot(root, reader: reader)
                completion?(reader.count)
            }
        }
    }

    public func reindexAll(roots: [String], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for root in roots {
                if let reader = try? self.store.reindex(root: root, ignore: self.ignore) {
                    self.service.setRoot(root, reader: reader)
                }
            }
            completion?()
        }
    }
}
