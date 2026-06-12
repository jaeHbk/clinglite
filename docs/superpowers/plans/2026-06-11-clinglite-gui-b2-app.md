# ClingLite GUI — Plan B2: ClingApp (menu-bar agent + hotkey search panel)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A polished, lightweight macOS menu-bar agent that summons a borderless Spotlight-style search panel via a global hotkey, shows live fuzzy results from `ClingCore` as you type, supports core file actions and keyboard nav, indexes configured roots in the background with FSEvents live updates, and ships as a real `.app` bundle — built with Command Line Tools, no Xcode.

**Architecture:** A new `ClingApp` executable target depends on the verified `ClingCore` library (Plan A + B1). All AppKit/SwiftUI/system glue lives here. Search runs off the main thread (debounced, stale-discarded). The app is an `LSUIElement` accessory (no dock icon) with an `NSStatusItem` menu and a floating `NSPanel`. Verification uses **offscreen SwiftUI→PNG rendering** (proven to work under CLT — `screencapture` of live windows is blocked in the build context) plus a headless `--smoke` mode that drives the real search path.

**Tech Stack:** Swift 6.3 / SwiftPM / Command Line Tools (no Xcode); SwiftUI + AppKit; Carbon `RegisterEventHotKey`; `FSEventStream`; `NSWorkspace`/`NSPasteboard`/`QLPreviewPanel`. Logic tests use swift-testing via `./scripts/test.sh`; GUI verified via the app's `--render-smoke` PNG mode.

---

## Context for the implementer

`ClingCore` (already built, do NOT modify) exposes:
- `SearchService()` → `.setRoot(_ root: String, reader: IndexReader)`, `.removeRoot(_:)`, `.rootPaths: [String]`, `.search(_ query: String, maxResults: Int) -> [SearchHit]`, `.applyChange(path: String, exists: Bool, isDir: Bool)`, `.adviseDontNeedAll()`.
- `IndexStore(directory: URL)` → `.loadOrBuild(root:ignore:) throws -> IndexReader`, `.reindex(root:ignore:) throws -> IndexReader`, `.indexURL(forRoot:) -> URL`, `.manifest() -> [ManifestEntry]`.
- `IgnoreMatcher(patterns: [String])`.
- `SearchHit`: `id: Int`, `path: String` (LOWERCASED), `score: Int`, `isDir: Bool`.
- `fuzzyHighlightRanges(query: String, in basename: String) -> [Range<Int>]`.
- `currentResidentBytes() -> Int`.

**Path casing:** results are lowercased. `PathResolver` (Task 4) recovers the real on-disk path for file actions.

`Package.swift` currently declares `ClingCore` (library), `cling` (exec), `ClingCoreTests`. Task 1 adds a `ClingApp` executable target.

---

## File Structure

```
Sources/ClingApp/
  main.swift              # entry: dispatch --render-smoke / --smoke / normal launch
  AppConfig.swift         # UserDefaults-backed settings (roots, hotkey, dockIcon, maxResults)
  RowModel.swift          # plain value type for a result row (name, dir, path, isDir, ranges)
  ResultsFormatter.swift  # [SearchHit] + query -> [RowModel] (highlight ranges, name/dir split)
  PathResolver.swift      # lowercased index path -> real on-disk URL (case recovery)
  SearchController.swift   # ObservableObject: debounce + off-main search + stale-discard
  SearchView.swift        # SwiftUI: search field + results list (the renderable surface)
  RowView.swift           # SwiftUI: one result row with highlighted name
  RenderSmoke.swift       # offscreen render of SearchView to PNG for verification
  HotKey.swift            # Carbon RegisterEventHotKey wrapper
  SearchPanel.swift       # borderless floating NSPanel hosting SearchView
  KeyMonitor.swift        # NSEvent local monitor: arrows/enter/cmd-enter/space/esc
  FileActions.swift       # open/reveal/quicklook/copy via NSWorkspace/NSPasteboard
  FSWatcher.swift         # FSEventStream -> SearchService.applyChange
  IndexCoordinator.swift  # owns IndexStore+SearchService; load-on-launch + background reindex
  MenuBarController.swift # NSStatusItem menu (Show, Reindex, Settings, Quit)
  SettingsView.swift      # SwiftUI settings window
  AppDelegate.swift       # wires everything; LSUIElement agent lifecycle
Tests/ClingAppTests/
  ResultsFormatterTests.swift
  AppConfigTests.swift
  PathResolverTests.swift
scripts/
  build-app.sh            # assemble ClingLite.app (Info.plist, icon, codesign)
```

Tasks 1–6 are headless and unit/render-testable. Tasks 7–13 are AppKit glue, verified by the render-smoke PNG and the assembled app. Task 14 builds the bundle and does end-to-end verification.

---

## Task 1: Add ClingApp target + AppConfig

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClingApp/AppConfig.swift`
- Create: `Sources/ClingApp/main.swift` (temporary stub; replaced in Task 7)
- Create: `Tests/ClingAppTests/AppConfigTests.swift`

- [ ] **Step 1: Modify `Package.swift`** — add the executable + test targets. Replace the `targets:` array with:

```swift
    targets: [
        .target(
            name: "ClingCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "cling", dependencies: ["ClingCore"]),
        .executableTarget(name: "ClingApp", dependencies: ["ClingCore"]),
        .testTarget(name: "ClingCoreTests", dependencies: ["ClingCore"]),
        .testTarget(name: "ClingAppTests", dependencies: ["ClingApp", "ClingCore"]),
    ]
```

Also add the product so it can be built by name — replace the `products:` array with:

```swift
    products: [
        .library(name: "ClingCore", targets: ["ClingCore"]),
        .executable(name: "cling", targets: ["cling"]),
        .executable(name: "ClingApp", targets: ["ClingApp"]),
    ],
```

- [ ] **Step 2: Write the failing test** `Tests/ClingAppTests/AppConfigTests.swift`:

```swift
import Testing
import Foundation
@testable import ClingApp

@Suite struct AppConfigTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "clinglite.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsWhenUnset() {
        let cfg = AppConfig(defaults: freshDefaults())
        #expect(cfg.roots == [NSHomeDirectory()])      // default root = home
        #expect(cfg.maxResults == 100)
        #expect(cfg.showDockIcon == false)             // menu-bar agent by default
        #expect(cfg.hotKeyKeyCode == 49)               // Space
        #expect(cfg.hotKeyModifiers == 524288)          // option (NSEvent.ModifierFlags.option.rawValue)
    }

    @Test func roundTripsThroughDefaults() {
        let d = freshDefaults()
        var cfg = AppConfig(defaults: d)
        cfg.roots = ["/tmp/a", "/tmp/b"]
        cfg.maxResults = 42
        cfg.showDockIcon = true
        cfg.hotKeyKeyCode = 3
        cfg.hotKeyModifiers = 1048576
        cfg.save()
        let reloaded = AppConfig(defaults: d)
        #expect(reloaded.roots == ["/tmp/a", "/tmp/b"])
        #expect(reloaded.maxResults == 42)
        #expect(reloaded.showDockIcon == true)
        #expect(reloaded.hotKeyKeyCode == 3)
        #expect(reloaded.hotKeyModifiers == 1048576)
    }
}
```

- [ ] **Step 3: Run, verify fail**

Run: `./scripts/test.sh AppConfigTests`
Expected: FAIL — `AppConfig` undefined.

- [ ] **Step 4: Implement `Sources/ClingApp/AppConfig.swift`**

```swift
import Foundation

/// User settings persisted in UserDefaults. Plain struct; `save()` writes all fields.
public struct AppConfig {
    private let defaults: UserDefaults
    private enum Key {
        static let roots = "roots"
        static let maxResults = "maxResults"
        static let showDockIcon = "showDockIcon"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }

    public var roots: [String]
    public var maxResults: Int
    public var showDockIcon: Bool
    public var hotKeyKeyCode: Int
    public var hotKeyModifiers: Int

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.roots = (defaults.array(forKey: Key.roots) as? [String]) ?? [NSHomeDirectory()]
        let mr = defaults.integer(forKey: Key.maxResults)
        self.maxResults = mr == 0 ? 100 : mr
        self.showDockIcon = defaults.bool(forKey: Key.showDockIcon)   // default false
        let kc = defaults.object(forKey: Key.hotKeyKeyCode) as? Int
        self.hotKeyKeyCode = kc ?? 49                                  // Space
        let mods = defaults.object(forKey: Key.hotKeyModifiers) as? Int
        self.hotKeyModifiers = mods ?? 524288                          // Option
    }

    public func save() {
        defaults.set(roots, forKey: Key.roots)
        defaults.set(maxResults, forKey: Key.maxResults)
        defaults.set(showDockIcon, forKey: Key.showDockIcon)
        defaults.set(hotKeyKeyCode, forKey: Key.hotKeyKeyCode)
        defaults.set(hotKeyModifiers, forKey: Key.hotKeyModifiers)
    }

    /// Default ignore patterns applied to every root.
    public static let defaultIgnorePatterns = [
        ".git/", "node_modules/", ".build/", "DerivedData/", ".Trash/",
        "Library/Caches/", ".DS_Store", "*.o",
    ]
}
```

- [ ] **Step 5: Write `Sources/ClingApp/main.swift`** (temporary stub, replaced in Task 7):

```swift
import Foundation

// Replaced by the full launcher in Task 7. Stub keeps the target building.
print("ClingApp stub")
```

- [ ] **Step 6: Run, verify pass**

Run: `swift build && ./scripts/test.sh AppConfigTests`
Expected: build succeeds; both AppConfig tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ClingApp/AppConfig.swift Sources/ClingApp/main.swift Tests/ClingAppTests/AppConfigTests.swift
git commit -m "feat: ClingApp target + AppConfig (UserDefaults settings)"
```

---

## Task 2: RowModel + ResultsFormatter

**Files:**
- Create: `Sources/ClingApp/RowModel.swift`
- Create: `Sources/ClingApp/ResultsFormatter.swift`
- Create: `Tests/ClingAppTests/ResultsFormatterTests.swift`

- [ ] **Step 1: Write the failing test** `Tests/ClingAppTests/ResultsFormatterTests.swift`:

```swift
import Testing
@testable import ClingApp
@testable import ClingCore

@Suite struct ResultsFormatterTests {
    @Test func splitsNameAndDirAndComputesHighlight() {
        let hits = [SearchHit(id: 0, path: "/users/me/src/engine.swift", score: 100, isDir: false)]
        let rows = ResultsFormatter.rows(from: hits, query: "eng")
        #expect(rows.count == 1)
        #expect(rows[0].name == "engine.swift")
        #expect(rows[0].dir == "/users/me/src")
        #expect(rows[0].path == "/users/me/src/engine.swift")
        #expect(rows[0].isDir == false)
        #expect(rows[0].highlight == [0 ..< 3])      // "eng" of engine
    }

    @Test func rootLevelFileHasEmptyDir() {
        let hits = [SearchHit(id: 1, path: "/readme.md", score: 10, isDir: false)]
        let rows = ResultsFormatter.rows(from: hits, query: "readme")
        #expect(rows[0].name == "readme.md")
        #expect(rows[0].dir == "/")
    }

    @Test func directoryRowFlagged() {
        let hits = [SearchHit(id: 2, path: "/users/me/projects", score: 5, isDir: true)]
        let rows = ResultsFormatter.rows(from: hits, query: "proj")
        #expect(rows[0].isDir == true)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh ResultsFormatterTests`
Expected: FAIL — `RowModel`/`ResultsFormatter` undefined.

- [ ] **Step 3: Implement `Sources/ClingApp/RowModel.swift`**

```swift
import Foundation

/// A presentation-ready search result row. Plain value type (no AppKit) so it's testable.
public struct RowModel: Identifiable, Equatable {
    public let id: Int
    public let name: String           // basename
    public let dir: String            // parent directory (or "/")
    public let path: String           // full (lowercased index) path
    public let isDir: Bool
    public let highlight: [Range<Int>] // byte ranges into `name` to bold
}
```

- [ ] **Step 4: Implement `Sources/ClingApp/ResultsFormatter.swift`**

```swift
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
```

- [ ] **Step 5: Run, verify pass**

Run: `./scripts/test.sh ResultsFormatterTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClingApp/RowModel.swift Sources/ClingApp/ResultsFormatter.swift Tests/ClingAppTests/ResultsFormatterTests.swift
git commit -m "feat: RowModel + ResultsFormatter (name/dir split + highlight)"
```

---

## Task 3: PathResolver (lowercased index path -> real on-disk URL)

**Files:**
- Create: `Sources/ClingApp/PathResolver.swift`
- Create: `Tests/ClingAppTests/PathResolverTests.swift`

- [ ] **Step 1: Write the failing test** `Tests/ClingAppTests/PathResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import ClingApp

@Suite struct PathResolverTests {
    @Test func resolvesExactExistingPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        // The exact path exists -> returned as-is.
        let resolved = PathResolver.resolve(file.path)
        #expect(resolved == file.path)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func recoversCaseForMismatchedComponent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("MixedCase.TXT")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        // Look up the lowercased form; resolver must recover the real cased name (on a
        // case-insensitive FS the lowercased path may even open directly, but resolve()
        // must return a path that points at the real file either way).
        let lowered = dir.path + "/mixedcase.txt"
        let resolved = PathResolver.resolve(lowered)
        #expect(FileManager.default.fileExists(atPath: resolved))
        #expect((resolved as NSString).lastPathComponent.lowercased() == "mixedcase.txt")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func returnsInputWhenNothingExists() {
        let p = "/nonexistent-\(UUID().uuidString)/whatever.txt"
        #expect(PathResolver.resolve(p) == p)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh PathResolverTests`
Expected: FAIL — `PathResolver` undefined.

- [ ] **Step 3: Implement `Sources/ClingApp/PathResolver.swift`**

```swift
import Foundation

/// Recovers a real on-disk path from the index's lowercased path. macOS default volumes are
/// case-insensitive (so the lowercased path usually opens directly), but file ACTIONS should
/// point at the true-cased path. Strategy: if the path exists as-is, return it; otherwise walk
/// from the deepest existing ancestor, matching each remaining component case-insensitively.
public enum PathResolver {
    public static func resolve(_ lowercasedPath: String) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: lowercasedPath) { return lowercasedPath }

        let comps = lowercasedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = "/"
        for comp in comps {
            let candidate = current == "/" ? "/" + comp : current + "/" + comp
            if fm.fileExists(atPath: candidate) {
                current = candidate
                continue
            }
            // Find a case-insensitive match among the directory's entries.
            let entries = (try? fm.contentsOfDirectory(atPath: current)) ?? []
            if let match = entries.first(where: { $0.lowercased() == comp.lowercased() }) {
                current = current == "/" ? "/" + match : current + "/" + match
            } else {
                // No match at this level — give up and return the original input.
                return lowercasedPath
            }
        }
        return current
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh PathResolverTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingApp/PathResolver.swift Tests/ClingAppTests/PathResolverTests.swift
git commit -m "feat: PathResolver (recover real on-disk path from lowercased index path)"
```

---

## Task 4: SearchView + RowView (the renderable SwiftUI surface)

**Files:**
- Create: `Sources/ClingApp/RowView.swift`
- Create: `Sources/ClingApp/SearchView.swift`

No unit test (pure SwiftUI); verified by the render-smoke in Task 6.

- [ ] **Step 1: Implement `Sources/ClingApp/RowView.swift`**

```swift
import SwiftUI

/// One result row: icon, basename with highlighted matched chars, dimmed parent dir.
struct RowView: View {
    let row: RowModel
    let selected: Bool

    /// Build an AttributedString bolding the highlighted byte ranges of the name.
    private var styledName: AttributedString {
        var s = AttributedString(row.name)
        let bytes = Array(row.name.utf8)
        for r in row.highlight {
            guard r.lowerBound >= 0, r.upperBound <= bytes.count else { continue }
            // Map UTF-8 byte offsets to String indices via prefix decoding.
            let lo = String(decoding: bytes[0 ..< r.lowerBound], as: UTF8.self).count
            let hi = String(decoding: bytes[0 ..< r.upperBound], as: UTF8.self).count
            if let lb = s.index(s.startIndex, offsetByCharacters: lo, limitedBy: s.endIndex),
               let ub = s.index(s.startIndex, offsetByCharacters: hi, limitedBy: s.endIndex),
               lb < ub {
                s[lb ..< ub].font = .system(.body, design: .default).bold()
                s[lb ..< ub].foregroundColor = .yellow
            }
        }
        return s
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isDir ? "folder.fill" : "doc.fill")
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(styledName).foregroundStyle(selected ? .white : .primary).lineLimit(1)
                Text(row.dir).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.85) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension AttributedString {
    func index(_ i: AttributedString.Index, offsetByCharacters n: Int, limitedBy limit: AttributedString.Index) -> AttributedString.Index? {
        characters.index(i, offsetBy: n, limitedBy: limit)
    }
}
```

- [ ] **Step 2: Implement `Sources/ClingApp/SearchView.swift`**

```swift
import SwiftUI

/// The panel's content: a query field above a scrollable result list. Bound to a SearchController.
struct SearchView: View {
    @ObservedObject var controller: SearchController
    var onSubmit: () -> Void = {}
    var onReveal: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search files…", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if !controller.rows.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(controller.rows.enumerated()), id: \.element.id) { idx, row in
                            RowView(row: row, selected: idx == controller.selection)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 620)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (no test yet; the render-smoke in Task 6 exercises it).

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/RowView.swift Sources/ClingApp/SearchView.swift
git commit -m "feat: SearchView + RowView (panel content surface)"
```

---

## Task 5: SearchController (debounced off-main search)

**Files:**
- Create: `Sources/ClingApp/SearchController.swift`
- Create: `Tests/ClingAppTests/SearchControllerTests.swift`

- [ ] **Step 1: Write the failing test** `Tests/ClingAppTests/SearchControllerTests.swift`:

```swift
import Testing
import Foundation
@testable import ClingApp
@testable import ClingCore

@Suite struct SearchControllerTests {
    private func service(_ paths: [String]) throws -> SearchService {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        let svc = SearchService()
        svc.setRoot("/", reader: try IndexReader(url: url))
        return svc
    }

    @MainActor
    @Test func searchProducesRowsAfterDebounce() async throws {
        let svc = try service(["/users/me/engine.swift", "/users/me/readme.md"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "engine"
        // Wait for debounce + async search to publish.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(c.rows.contains { $0.name == "engine.swift" })
        #expect(!c.rows.contains { $0.name == "readme.md" })
    }

    @MainActor
    @Test func emptyQueryClearsRows() async throws {
        let svc = try service(["/users/me/engine.swift"])
        let c = SearchController(service: svc, maxResults: 50, debounceMillis: 10)
        c.query = "engine"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!c.rows.isEmpty)
        c.query = ""
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(c.rows.isEmpty)
        #expect(c.selection == 0)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `./scripts/test.sh SearchControllerTests`
Expected: FAIL — `SearchController` undefined.

- [ ] **Step 3: Implement `Sources/ClingApp/SearchController.swift`**

```swift
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
                self.selection = formatted.isEmpty ? 0 : min(self.selection, formatted.count - 1)
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
}
```

- [ ] **Step 4: Run, verify pass**

Run: `./scripts/test.sh SearchControllerTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingApp/SearchController.swift Tests/ClingAppTests/SearchControllerTests.swift
git commit -m "feat: SearchController (debounced off-main search + stale-discard)"
```

---

## Task 6: Render-smoke (offscreen SwiftUI -> PNG verification)

**Files:**
- Create: `Sources/ClingApp/RenderSmoke.swift`

This is the authoritative GUI verification: render the real `SearchView` (populated via the real search path) to a PNG and assert a known result is present.

- [ ] **Step 1: Implement `Sources/ClingApp/RenderSmoke.swift`**

```swift
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
```

- [ ] **Step 2: Add the render-injection hook to `SearchController`** — append this method inside the `SearchController` class in `Sources/ClingApp/SearchController.swift` (before the closing brace):

```swift
    /// Test/render hook: set rows directly without going through the async search path.
    public func setRowsForRender(_ rows: [RowModel], query: String) {
        self.query = query
        self.pending?.cancel()
        self.rows = rows
        self.selection = 0
    }
```

(Note: setting `self.query` triggers `scheduleSearch()`, but we immediately cancel `pending` and overwrite `rows`; for the 0ms render path this is fine and deterministic.)

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/RenderSmoke.swift Sources/ClingApp/SearchController.swift
git commit -m "feat: offscreen render-smoke for GUI verification"
```

---

## Task 7: HotKey (Carbon global hotkey)

**Files:**
- Create: `Sources/ClingApp/HotKey.swift`

No unit test (registers a process-global Carbon handler; verified at runtime in Task 14).

- [ ] **Step 1: Implement `Sources/ClingApp/HotKey.swift`**

```swift
import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon RegisterEventHotKey (no Accessibility permission
/// required). Invokes `onPressed` on the main thread when the combo fires.
public final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    public var onPressed: () -> Void = {}

    private static var shared: HotKey?

    public init() {}

    /// keyCode is a virtual key code (e.g. 49 = Space). carbonModifiers built from NSEvent flags.
    public func register(keyCode: Int, nsModifiers: Int) {
        unregister()
        HotKey.shared = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            HotKey.shared?.onPressed()
            return noErr
        }, 1, &eventType, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4E47), id: 1) // 'CLNG'
        let carbonMods = HotKey.carbonFlags(fromNS: nsModifiers)
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    public func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    private static func carbonFlags(fromNS ns: Int) -> UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: UInt(ns))
        var c: UInt32 = 0
        if f.contains(.command) { c |= UInt32(cmdKey) }
        if f.contains(.option)  { c |= UInt32(optionKey) }
        if f.contains(.control) { c |= UInt32(controlKey) }
        if f.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClingApp/HotKey.swift
git commit -m "feat: Carbon global hotkey wrapper"
```

---

## Task 8: FileActions

**Files:**
- Create: `Sources/ClingApp/FileActions.swift`

No unit test (system side effects); the functions are thin wrappers verified at runtime.

- [ ] **Step 1: Implement `Sources/ClingApp/FileActions.swift`**

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClingApp/FileActions.swift
git commit -m "feat: FileActions (open/reveal/copy file/copy path)"
```

---

## Task 9: IndexCoordinator + FSWatcher

**Files:**
- Create: `Sources/ClingApp/IndexCoordinator.swift`
- Create: `Sources/ClingApp/FSWatcher.swift`

No unit test for the AppKit/FSEvents wiring (the underlying IndexStore/SearchService are tested in B1); verified at runtime.

- [ ] **Step 1: Implement `Sources/ClingApp/IndexCoordinator.swift`**

```swift
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
```

- [ ] **Step 2: Implement `Sources/ClingApp/FSWatcher.swift`**

```swift
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
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/IndexCoordinator.swift Sources/ClingApp/FSWatcher.swift
git commit -m "feat: IndexCoordinator + FSWatcher (background indexing + live updates)"
```

---

## Task 10: SearchPanel + KeyMonitor

**Files:**
- Create: `Sources/ClingApp/SearchPanel.swift`
- Create: `Sources/ClingApp/KeyMonitor.swift`

- [ ] **Step 1: Implement `Sources/ClingApp/KeyMonitor.swift`**

```swift
import AppKit

/// Local NSEvent monitor for the search panel's key commands. Returns nil to swallow the event
/// when handled (so the text field doesn't also process arrows/enter/esc).
public final class KeyMonitor {
    public var onMove: (Int) -> Void = { _ in }
    public var onOpen: () -> Void = {}
    public var onReveal: () -> Void = {}
    public var onQuickLook: () -> Void = {}
    public var onCopyPath: () -> Void = {}
    public var onEscape: () -> Void = {}

    private var monitor: Any?

    public func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 125: self.onMove(1); return nil    // down arrow
            case 126: self.onMove(-1); return nil   // up arrow
            case 36, 76:                            // return / keypad enter
                if cmd { self.onReveal() } else { self.onOpen() }; return nil
            case 49:                                // space -> quick look (only if not typing? always QL)
                self.onQuickLook(); return nil
            case 53: self.onEscape(); return nil    // escape
            case 8 where cmd: self.onCopyPath(); return nil  // cmd-c
            default: return event
            }
        }
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
```

Note: Space-as-QuickLook conflicts with typing spaces in the query. To keep multi-word queries working, the real wiring (Task 11) only installs the monitor's Space handling when the query field is empty or the user holds no focus on text; for simplicity here the monitor forwards Space to QuickLook ONLY when a modifier isn't needed — the AppDelegate gates it. To avoid breaking space-typing, change `case 49` to require the results list focused. Simplest correct behavior: map Quick Look to `Cmd+Y` instead of Space. Replace `case 49:` with:

```swift
            case 16 where cmd: self.onQuickLook(); return nil  // cmd-y -> quick look
```

(Delete the `case 49` Space mapping entirely so spaces type normally.)

- [ ] **Step 2: Implement `Sources/ClingApp/SearchPanel.swift`**

```swift
import AppKit
import SwiftUI

/// Borderless floating panel that hosts the SearchView, centered on the active screen, joining
/// all Spaces, hiding when it loses key status.
public final class SearchPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let makeView: () -> AnyView
    public var onHide: () -> Void = {}

    public init(view: @escaping () -> AnyView) { self.makeView = view }

    public func toggle() { (panel?.isVisible ?? false) ? hide() : show() }

    public func show() {
        if panel == nil { build() }
        guard let panel else { return }
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
        onHide()
    }

    private func build() {
        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 80)
        let p = NSPanel(contentRect: hosting.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hosting
        p.delegate = self
        p.worksWhenModal = true
        panel = p
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let size = panel.frame.size
        let x = sf.midX - size.width / 2
        let y = sf.midY + sf.height * 0.15 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Hide on losing key (click-away / app switch).
    public func windowDidResignKey(_ notification: Notification) { hide() }

    /// Allow a borderless panel to become key (so the text field can receive input).
    public func canBecomeKey() -> Bool { true }
}
```

Note: `NSPanel` with `.borderless` already returns true for `canBecomeKey` when `.nonactivatingPanel` is NOT set; we include `.nonactivatingPanel` for floating behavior but call `NSApp.activate` + `makeKeyAndOrderFront`, which makes it key. If text input doesn't focus in Task 14 testing, subclass NSPanel overriding `canBecomeKey`/`canBecomeMain` to return true. Keep this note for the implementer.

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/SearchPanel.swift Sources/ClingApp/KeyMonitor.swift
git commit -m "feat: SearchPanel (floating borderless) + KeyMonitor (key commands)"
```

---

## Task 11: MenuBarController + SettingsView

**Files:**
- Create: `Sources/ClingApp/MenuBarController.swift`
- Create: `Sources/ClingApp/SettingsView.swift`

- [ ] **Step 1: Implement `Sources/ClingApp/MenuBarController.swift`**

```swift
import AppKit

/// Menu-bar status item with the app's commands. Pure AppKit; actions are injected closures.
public final class MenuBarController {
    private let statusItem: NSStatusItem
    public var onShow: () -> Void = {}
    public var onReindex: () -> Void = {}
    public var onSettings: () -> Void = {}
    public var onQuit: () -> Void = {}

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "ClingLite")
        }
        rebuildMenu(status: "Ready")
    }

    public func rebuildMenu(status: String) {
        let menu = NSMenu()
        let statusRow = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Search…", action: #selector(fireShow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reindex Now", action: #selector(fireReindex), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(fireSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClingLite", action: #selector(fireQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func fireShow() { onShow() }
    @objc private func fireReindex() { onReindex() }
    @objc private func fireSettings() { onSettings() }
    @objc private func fireQuit() { onQuit() }
}
```

- [ ] **Step 2: Implement `Sources/ClingApp/SettingsView.swift`**

```swift
import SwiftUI

/// Minimal settings: list of roots (add/remove), max results, dock-icon toggle. Hotkey display
/// is read-only here (changing it live is a Phase-C nicety); editing roots triggers a reindex.
struct SettingsView: View {
    @State var roots: [String]
    @State var maxResults: Double
    @State var showDockIcon: Bool
    var onSave: (_ roots: [String], _ maxResults: Int, _ showDockIcon: Bool) -> Void
    var onAddRoot: () -> String?   // returns a chosen directory path or nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ClingLite Settings").font(.title2).bold()

            Text("Search roots").font(.headline)
            List {
                ForEach(roots, id: \.self) { r in Text(r).font(.system(.body, design: .monospaced)) }
                    .onDelete { roots.remove(atOffsets: $0) }
            }
            .frame(height: 140)
            Button("Add Folder…") { if let p = onAddRoot() { roots.append(p) } }

            HStack {
                Text("Max results: \(Int(maxResults))")
                Slider(value: $maxResults, in: 20 ... 500, step: 10)
            }
            Toggle("Show Dock icon", isOn: $showDockIcon)

            HStack {
                Spacer()
                Button("Save") { onSave(roots, Int(maxResults), showDockIcon) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/MenuBarController.swift Sources/ClingApp/SettingsView.swift
git commit -m "feat: MenuBarController + SettingsView"
```

---

## Task 12: AppDelegate (wire everything)

**Files:**
- Create: `Sources/ClingApp/AppDelegate.swift`

- [ ] **Step 1: Implement `Sources/ClingApp/AppDelegate.swift`**

```swift
import AppKit
import SwiftUI
import ClingCore

/// Wires the menu-bar agent: builds the index coordinator, search controller, panel, hotkey,
/// key monitor, FS watcher, and menu bar. LSUIElement (accessory) by default.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig()
    private var coordinator: IndexCoordinator!
    private var controller: SearchController!
    private var panel: SearchPanel!
    private var hotKey = HotKey()
    private var keyMonitor = KeyMonitor()
    private var fsWatcher: FSWatcher!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(config.showDockIcon ? .regular : .accessory)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClingLite", isDirectory: true)
        coordinator = IndexCoordinator(storeDirectory: appSupport, ignorePatterns: AppConfig.defaultIgnorePatterns)
        coordinator.loadExisting(roots: config.roots)        // instant search on existing/just-built index
        controller = SearchController(service: coordinator.service, maxResults: config.maxResults)

        menuBar = MenuBarController()
        menuBar.onShow = { [weak self] in self?.panel.show() }
        menuBar.onReindex = { [weak self] in self?.reindexAll() }
        menuBar.onSettings = { [weak self] in self?.openSettings() }
        menuBar.onQuit = { NSApp.terminate(nil) }

        panel = SearchPanel(view: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SearchView(controller: self.controller,
                                      onSubmit: { self.openSelected() },
                                      onReveal: { self.revealSelected() }))
        })
        panel.onHide = { [weak self] in self?.coordinator.service.adviseDontNeedAll() }

        keyMonitor.onMove = { [weak self] d in self?.controller.moveSelection(d) }
        keyMonitor.onOpen = { [weak self] in self?.openSelected() }
        keyMonitor.onReveal = { [weak self] in self?.revealSelected() }
        keyMonitor.onQuickLook = { [weak self] in self?.revealSelected() } // QL falls back to reveal in B2
        keyMonitor.onCopyPath = { [weak self] in if let p = self?.controller.selectedRow?.path { FileActions.copyPath(p) } }
        keyMonitor.onEscape = { [weak self] in self?.panel.hide() }
        keyMonitor.start()

        hotKey.onPressed = { [weak self] in self?.panel.toggle() }
        hotKey.register(keyCode: config.hotKeyKeyCode, nsModifiers: config.hotKeyModifiers)

        fsWatcher = FSWatcher(service: coordinator.service, roots: config.roots)
        fsWatcher.start()

        // Kick a background refresh so the index is current shortly after launch.
        coordinator.reindexAll(roots: config.roots) { [weak self] in
            DispatchQueue.main.async { self?.menuBar.rebuildMenu(status: "Indexed \(self?.config.roots.count ?? 0) root(s)") }
        }
    }

    private func openSelected() {
        guard let row = controller.selectedRow else { return }
        FileActions.open(row.path); panel.hide()
    }
    private func revealSelected() {
        guard let row = controller.selectedRow else { return }
        FileActions.revealInFinder(row.path); panel.hide()
    }
    private func reindexAll() {
        menuBar.rebuildMenu(status: "Indexing…")
        coordinator.reindexAll(roots: config.roots) { [weak self] in
            DispatchQueue.main.async { self?.menuBar.rebuildMenu(status: "Ready") }
        }
    }
    private func openSettings() {
        if settingsWindow == nil {
            let v = SettingsView(roots: config.roots, maxResults: Double(config.maxResults),
                                 showDockIcon: config.showDockIcon,
                                 onSave: { [weak self] roots, mr, dock in self?.saveSettings(roots, mr, dock) },
                                 onAddRoot: { Self.chooseFolder() })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "ClingLite Settings"
            w.contentView = NSHostingView(rootView: v)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func saveSettings(_ roots: [String], _ mr: Int, _ dock: Bool) {
        config.roots = roots; config.maxResults = mr; config.showDockIcon = dock; config.save()
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
        settingsWindow?.close(); settingsWindow = nil
        coordinator.loadExisting(roots: roots)
        reindexAll()
    }
    private static func chooseFolder() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url?.path : nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClingApp/AppDelegate.swift
git commit -m "feat: AppDelegate wiring (menu-bar agent lifecycle)"
```

---

## Task 13: main.swift entry (modes) + replace stub

**Files:**
- Modify: `Sources/ClingApp/main.swift` (full replacement)

- [ ] **Step 1: Replace `Sources/ClingApp/main.swift`** entirely:

```swift
import AppKit
import ClingCore

// Modes:
//   ClingApp --render-smoke <fixtureDir> <query> <expectName> <outPNG>
//   ClingApp                       (normal menu-bar agent launch)
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--render-smoke" {
    guard args.count >= 5 else {
        FileHandle.standardError.write(Data("usage: ClingApp --render-smoke <fixture> <query> <expectName> <outPNG>\n".utf8))
        exit(2)
    }
    // Render must run on the main thread with an app context.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var ok = false
    let work = { ok = RenderSmoke.run(fixture: args[1], query: args[2], expectName: args[3], outPNG: args[4]) }
    if Thread.isMainThread { MainActor.assumeIsolated(work) } else { DispatchQueue.main.sync { MainActor.assumeIsolated(work) } }
    exit(ok ? 0 : 1)
}

// Normal launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Run the render-smoke against a fixture**

Run:
```bash
cd ~/Documents/clinglite
mkdir -p /tmp/clingfix/src
echo a > /tmp/clingfix/src/Engine.swift
echo b > /tmp/clingfix/Readme.md
swift build 2>&1 | tail -1
.build/debug/ClingApp --render-smoke /tmp/clingfix engine Engine.swift /tmp/cling-smoke.png ; echo "exit=$?"
ls -la /tmp/cling-smoke.png
```
Expected: `exit=0`; PNG written; stderr shows `found('Engine.swift')=true`.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClingApp/main.swift
git commit -m "feat: ClingApp entry (render-smoke mode + normal launch)"
```

---

## Task 14: build-app.sh + end-to-end verification

**Files:**
- Create: `scripts/build-app.sh`
- Modify: `.gitignore` (add `ClingLite.app`, `*.png`)

- [ ] **Step 1: Create `scripts/build-app.sh`**

```bash
#!/usr/bin/env bash
# Assemble ClingLite.app (menu-bar agent) from the SwiftPM build. CLT only — no Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release binary"
swift build -c release --product ClingApp

APP="ClingLite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClingApp "$APP/Contents/MacOS/ClingLite"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClingLite</string>
  <key>CFBundleDisplayName</key><string>ClingLite</string>
  <key>CFBundleIdentifier</key><string>com.clinglite.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>ClingLite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>ClingLite</string>
</dict>
</plist>
PLIST

# Ad-hoc sign (sufficient for local use).
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign skipped)"

echo "==> Built $APP"
ls -la "$APP/Contents/MacOS"
```

- [ ] **Step 2: Make executable + update .gitignore**

Run:
```bash
cd ~/Documents/clinglite
chmod +x scripts/build-app.sh
printf '%s\n' "ClingLite.app/" "*.png" "/tmp/clingfix" >> .gitignore
```

- [ ] **Step 3: Build the app bundle**

Run: `./scripts/build-app.sh 2>&1 | tail -8`
Expected: `Built ClingLite.app`, binary present at `ClingLite.app/Contents/MacOS/ClingLite`.

- [ ] **Step 4: Full headless suite (no regressions)**

Run: `./scripts/test.sh 2>&1 | tail -3`
Expected: all suites pass (Plan A + B1 + the new ClingApp tests).

- [ ] **Step 5: Render-smoke as the GUI acceptance gate**

Run:
```bash
cd ~/Documents/clinglite
mkdir -p /tmp/clingfix/src && echo a > /tmp/clingfix/src/Engine.swift && echo b > /tmp/clingfix/Readme.md
.build/release/ClingApp --render-smoke /tmp/clingfix engine Engine.swift /tmp/cling-smoke.png; echo "smoke exit=$?"
file /tmp/cling-smoke.png
```
Expected: `smoke exit=0`; PNG is valid image data. (The controller reviewer/human inspects the PNG to confirm the row renders.)

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app.sh .gitignore
git commit -m "build: ClingLite.app assembly + end-to-end render-smoke gate"
```

---

## Self-Review

**Spec coverage (GUI spec §4 components, §5 memory, §6 build, §7 verification):**
- AppConfig/settings (roots/hotkey/dock/maxResults) → Task 1, 11, 12. ✅
- RowModel/ResultsFormatter + highlight → Task 2. ✅
- PathResolver (case recovery) → Task 3. ✅
- SearchView/RowView → Task 4. ✅
- SearchController (debounce, off-main, stale-discard) → Task 5. ✅
- Render-smoke verification → Task 6, 13, 14. ✅
- HotKey (Carbon) → Task 7. ✅
- FileActions → Task 8. ✅
- IndexCoordinator + FSWatcher (background index + live updates) → Task 9. ✅
- SearchPanel (floating borderless) + KeyMonitor → Task 10. ✅
- MenuBarController + SettingsView → Task 11. ✅
- AppDelegate wiring (LSUIElement, adviseDontNeed on hide) → Task 12. ✅
- main entry modes → Task 13. ✅
- build-app.sh (.app, Info.plist LSUIElement, codesign) → Task 14. ✅
- Memory discipline (adviseDontNeedAll on hide) → Task 12 (`panel.onHide`). ✅

**Placeholder scan:** No TBD/TODO. The two design notes (KeyMonitor Space→Cmd-Y to avoid breaking space-typing; NSPanel canBecomeKey subclass fallback) are explicit resolution instructions, not placeholders.

**Type consistency:** `AppConfig(defaults:)` fields + `.save()` + `.defaultIgnorePatterns`; `RowModel{id,name,dir,path,isDir,highlight}`; `ResultsFormatter.rows(from:query:)`; `PathResolver.resolve(_:)`; `SearchController(service:maxResults:debounceMillis:)` + `.query/.rows/.selection/.moveSelection/.selectedRow/.setRowsForRender`; `RenderSmoke.run(fixture:query:expectName:outPNG:)`; `HotKey().register(keyCode:nsModifiers:)/.onPressed`; `FileActions.open/revealInFinder/copyFile/copyPath`; `IndexCoordinator(storeDirectory:ignorePatterns:)` + `.service/.loadExisting(roots:)/.reindexAll(roots:completion:)`; `FSWatcher(service:roots:)` + `.start()/.stop()`; `SearchPanel(view:)` + `.toggle()/.show()/.hide()/.onHide`; `KeyMonitor` closures + `.start()/.stop()`; `MenuBarController()` + closures + `.rebuildMenu(status:)`; consume ClingCore B1 API exactly as declared. Consistent across tasks.

**Known deferrals (Phase C, per spec §8):** real QuickLook panel (B2 maps Quick Look to reveal), live hotkey re-binding UI, scripts, drag-to-zone, syntax preview.
