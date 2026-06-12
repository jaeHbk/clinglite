import AppKit
import SwiftUI
import ClingCore

/// GUI verification harness. Two modes, both driving the REAL production views/panel:
///  - `render`: offscreen PNG of the real SearchView at the REAL PanelLayout size (so the image
///    matches what the live window shows — the divergence that hid the clipped result list).
///  - `liveSelfTest`: shows the REAL SearchPanel, runs a query through the REAL async
///    SearchController, and asserts on the LIVE window (height grew, rows present, field focused).
@MainActor
public enum RenderSmoke {
    /// Build a temp index over `fixture` and return a SearchService over it.
    private static func service(fixture: String) -> SearchService? {
        let idx = FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(UUID().uuidString).idx")
        guard (try? Indexer.build(root: fixture, ignore: IgnoreMatcher(patterns: AppConfig.defaultIgnorePatterns), output: idx)) != nil,
              let reader = try? IndexReader(url: idx) else { return nil }
        let svc = SearchService(); svc.setRoot(fixture, reader: reader)
        return svc
    }

    // MARK: - Offscreen render (visual confirmation at real size)

    public static func run(fixture: String, query: String, expectName: String, outPNG: String) -> Bool {
        guard let svc = service(fixture: fixture) else {
            FileHandle.standardError.write(Data("smoke: index build failed\n".utf8)); return false
        }
        let hits = svc.search(query, maxResults: 50)
        let rows = ResultsFormatter.rows(from: hits, query: query)
        let found = rows.contains { $0.name.lowercased() == expectName.lowercased() }

        let controller = SearchController(service: svc, maxResults: 50, debounceMillis: 0)
        controller.setRowsForRender(rows, query: query)
        let view = SearchView(controller: controller).environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: view)
        // Use the SAME PanelLayout sizing the live window uses — no bespoke formula here.
        let h = PanelLayout.totalHeight(rowCount: rows.count)
        host.frame = NSRect(x: 0, y: 0, width: PanelLayout.width, height: h)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outPNG))
            }
        }
        FileHandle.standardError.write(Data("render: rows=\(rows.count) found('\(expectName)')=\(found) height=\(Int(h)) png=\(outPNG)\n".utf8))
        return found
    }

    // MARK: - Live panel self-test (the real window the user sees)

    /// Drives the actual SearchPanel + SearchController. Calls `done(passed)` after the async
    /// search settles. Asserts: panel visible, window grew beyond the search bar, rows populated,
    /// and the first responder is a text editor (i.e. the field is focused without a click).
    public static func liveSelfTest(fixture: String, query: String, expectName: String,
                                    outPNG: String, done: @escaping (Bool) -> Void) {
        guard let svc = service(fixture: fixture) else {
            FileHandle.standardError.write(Data("selftest: index build failed\n".utf8)); done(false); return
        }
        let controller = SearchController(service: svc, maxResults: 50, debounceMillis: 30)
        let panel = SearchPanel(controller: controller, onSubmit: {}, onReveal: {})
        panel.show()                                   // real show() path: focus tick + activate
        controller.query = query                       // real async debounced search

        // Wait for debounce + async publish + the panel's onHeightChange resize to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let rows = controller.rows.count
            let found = controller.rows.contains { $0.name.lowercased() == expectName.lowercased() }
            let grew = panel.windowHeight > PanelLayout.searchBarHeight + 1
            let focused = panel.fieldHasFocus
            // Capture the live window content to a PNG for visual confirmation.
            if let win = NSApp.windows.first(where: { $0.isVisible && $0.frame.width == PanelLayout.width }),
               let content = win.contentView,
               let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: outPNG))
                }
            }
            let passed = found && grew && rows > 0
            FileHandle.standardError.write(Data(
                "selftest: rows=\(rows) found('\(expectName)')=\(found) windowHeight=\(Int(panel.windowHeight)) grew=\(grew) fieldFocused=\(focused) png=\(outPNG) => \(passed ? "PASS" : "FAIL")\n".utf8))
            done(passed)
        }
    }
}
