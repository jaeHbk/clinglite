import Foundation
import Combine
import ClingCore

/// Drives search off the main thread with debounce and stale-result discard, publishing
/// `[RowModel]` + a selection index on the main actor for SwiftUI to render.
@MainActor
public final class SearchController: ObservableObject {
    @Published public var query: String = "" { didSet { scheduleSearch() } }
    @Published public private(set) var rows: [RowModel] = []
    @Published public var selection: Int = 0

    private let service: SearchService
    private let maxResults: Int
    private let debounce: TimeInterval
    private let workQueue = DispatchQueue(label: "clinglite.search", qos: .userInitiated)
    private var seq: UInt64 = 0
    private var pending: DispatchWorkItem?

    public init(service: SearchService, maxResults: Int = 100, debounceMillis: Int = 60) {
        self.service = service
        self.maxResults = maxResults
        self.debounce = Double(debounceMillis) / 1000.0
    }

    private func scheduleSearch() {
        pending?.cancel()
        let q = query
        seq &+= 1
        let mySeq = seq
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            rows = []; selection = 0; return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let hits = self.service.search(q, maxResults: self.maxResults)
            let formatted = ResultsFormatter.rows(from: hits, query: q)
            Task { @MainActor in
                guard mySeq == self.seq else { return }  // discard stale results
                self.rows = formatted
                // A newly-published result set always selects the top row, so the highlighted
                // row and the preview match what the user is looking at. Selection only moves
                // away from 0 via arrow keys (moveSelection), within the current result set.
                self.selection = 0
                Diag.log("[publish] q='\(q)' rows=\(formatted.count) top3=\(formatted.prefix(3).map { $0.name }) sel=0 selectedRow='\(self.selectedRow?.name ?? "nil")'")
            }
        }
        pending = item
        workQueue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    public func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = max(0, min(rows.count - 1, selection + delta))
    }

    public var selectedRow: RowModel? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// Re-run the current query (e.g. after a rename changed the index). Clean replacement for
    /// toggling `query`; reuses the debounced off-main search path.
    public func refresh() { scheduleSearch() }

    /// Test/render hook: set rows directly without going through the async search path.
    public func setRowsForRender(_ rows: [RowModel], query: String) {
        self.query = query
        self.pending?.cancel()
        self.rows = rows
        self.selection = 0
    }
}
