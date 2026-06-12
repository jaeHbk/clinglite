import AppKit
import SwiftUI
import ClingCore

/// Offscreen verification: build a temp index over a fixture tree, run a query through the real
/// SearchController + SearchView, render the view to a PNG, and assert the expected result row
/// is present. Returns true on success. Used by `ClingApp --render-smoke`.
@MainActor
public enum RenderSmoke {
    public static func run(fixture: String, query: String, expectName: String, outPNG: String) -> Bool {
        let idx = FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(UUID().uuidString).idx")
        defer { try? FileManager.default.removeItem(at: idx) }
        do {
            _ = try Indexer.build(root: fixture, ignore: IgnoreMatcher(patterns: AppConfig.defaultIgnorePatterns), output: idx)
        } catch { FileHandle.standardError.write(Data("smoke: index build failed: \(error)\n".utf8)); return false }
        guard let reader = try? IndexReader(url: idx) else { return false }
        let svc = SearchService(); svc.setRoot(fixture, reader: reader)

        // Run the search synchronously (bypass debounce) to populate rows deterministically.
        let hits = svc.search(query, maxResults: 50)
        let rows = ResultsFormatter.rows(from: hits, query: query)
        let found = rows.contains { $0.name.lowercased() == expectName.lowercased() }

        let controller = SearchController(service: svc, maxResults: 50, debounceMillis: 0)
        controller.setRowsForRender(rows, query: query)
        let view = SearchView(controller: controller)
            .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: max(120, CGFloat(80 + rows.count * 34)))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: outPNG))
        }
        FileHandle.standardError.write(Data("smoke: rows=\(rows.count) found('\(expectName)')=\(found) png=\(outPNG)\n".utf8))
        return found
    }
}
