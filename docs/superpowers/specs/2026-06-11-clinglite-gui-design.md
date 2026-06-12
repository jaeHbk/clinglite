# ClingLite GUI (Plan B) — Design Spec

**Date:** 2026-06-11
**Goal:** A polished, lightweight macOS GUI for ClingLite — a Spotlight/Alfred-style instant fuzzy file finder — wrapping the verified `ClingCore` engine. Menu-bar agent summoned by a global hotkey, live results as you type, core file actions, background indexing with FSEvents live updates. Built with Command Line Tools only (no Xcode), no paywall/telemetry, holding the project's <500MB memory discipline at the app level.

---

## 1. Context

Plan A delivered `ClingCore`: a dependency-free SwiftPM library + `cling` CLI with a memory-mapped structure-of-arrays index, basename-focused fuzzy search, fts(3) indexer, and base+delta live updates. Proven: real `~/Documents` (151,749 files) → 23MB search RSS, ~18ms search; 2M-file synthetic → 77MB, ~80ms. 40 tests green debug+release.

This machine has a live **Aqua GUI session** with `screencapture`, `osascript`/System Events, `open`, `iconutil`, `actool`, `codesign`, `plutil` — so the GUI can be launched, driven, and screenshotted for real verification, no Xcode needed.

### ClingCore public API the app consumes (Plan A, verbatim)

- `IndexReader(url:) throws` — mmap a `.idx`; `.count`, `.path(_:)`, `.adviseDontNeed()`.
- `IndexWriter.write(entries:to:) throws`; `RawEntry(path:isDir:)`.
- `Indexer.build(root:ignore:output:) throws -> Int`; `IgnoreMatcher(patterns:)`/`(text:)`.
- `SearchEngine(reader:)` + `.search(_:maxResults:) -> [SearchHit]` (`SearchHit`: `id, path, score, isDir`).
- `LiveIndex(base:)` + `.add(_:)`, `.remove(path:)`, `.search(_:maxResults:)`.
- `FileWalker(ignore:)`, `currentResidentBytes()`, `ParsedQuery(_:)`.

---

## 2. Decisions (locked)

1. **Scope:** Polished core GUI. Borderless search panel, live results, keyboard nav, core file actions (Open / Reveal in Finder / Quick Look / Copy file / Copy path), global hotkey, background indexing + FSEvents live updates, settings (roots / hotkey / dock-icon), real `.app` bundle. Defers the long tail to Phase C.
2. **App mode:** Menu-bar agent (`LSUIElement`), summoned by a global hotkey as a floating borderless panel; hides on blur. Dock-icon toggle in settings.
3. **Build:** SwiftPM + Command Line Tools, no Xcode. Manual `.app` assembly.
4. **Hotkey default:** ⌥Space (Option+Space), configurable.
5. **Default root:** `~` (configurable). Default ignores: `.git`, `node_modules`, `.build`, `DerivedData`, `Library/Caches`, `.Trash`.

---

## 3. Architecture

Two layers, clean boundary:

- **ClingCore (pure, headless, unit-tested — no AppKit):** the Plan A engine plus a thin **orchestration layer** that is still pure Swift and fully testable without a GUI:
  - `SearchService` — thread-safe facade over N roots (each a `LiveIndex`); cross-root merge/dedup/rank; routes FS changes to the right root by longest-prefix; swaps in freshly-reindexed bases.
  - `IndexStore` — persistent `.idx` + manifest under Application Support; `loadOrBuild` / `reindex`.
  - `LiveIndex` enhancement — cached delta reader (rebuild only on delta mutation, not per search).
  - `highlightRanges(query:basename:)` — matched-character ranges for result bolding.
- **ClingApp (new executable target — all AppKit/SwiftUI/system):** windowing, hotkey, key handling, file actions, FSEvents, menu bar, settings. Calls ClingCore off the main thread.

**Why this split:** all the hard logic stays in the testable library; the app target holds only thin, mostly-declarative glue that's verified by launching the real app. Files stay small and single-purpose.

### Data flow

```
global hotkey ──► AppDelegate.togglePanel ──► SearchPanel (NSPanel, key)
                                                    │ text changes
                                                    ▼
                              SearchController (debounce 60ms, serial bg queue)
                                                    │ search(query) off-main
                                                    ▼
                                       SearchService ──► per-root LiveIndex ──► SearchEngine
                                                    │ [SearchHit] (stale results discarded by seq)
                                                    ▼
                              MainActor: publish results ──► SearchView/ResultRow (highlighted)
                                                    │ ⏎ / ⌘⏎ / Space / Esc
                                                    ▼
                                              FileActions (NSWorkspace / NSPasteboard / QL)

FSEventStream ──► SearchService.applyChange(path:exists:isDir:) ──► right root's LiveIndex
(debounced) ───► background full reindex ──► IndexStore.reindex ──► SearchService.replaceBase
```

---

## 4. Components (ClingApp)

| File | Responsibility |
|---|---|
| `main.swift` | Entry: parse `--smoke`/`--reindex` flags else launch NSApplication with AppDelegate. |
| `AppDelegate.swift` | `LSUIElement` agent; owns `SearchService`, `IndexCoordinator`, `MenuBarController`, `HotKey`, `SearchPanel`; lifecycle. |
| `HotKey.swift` | Carbon `RegisterEventHotKey` wrapper (no dependency); register/unregister; callback. |
| `SearchPanel.swift` | Borderless floating `NSPanel`, `canBecomeKey=true`, `.nonactivatingPanel` off (it activates), centered on active screen, joins all Spaces, hides on resignKey. Hosts `SearchView`. |
| `SearchController.swift` | `ObservableObject`; query text → 60ms debounce → serial background `DispatchQueue` → `SearchService.search`; sequence-number stale-discard; publishes `[Row]` + selection on MainActor. |
| `SearchView.swift` | SwiftUI: search field + results list, bound to `SearchController`. |
| `ResultRow.swift` | One row: file icon (`NSWorkspace.icon(forFile:)`, cached, downsampled), name with highlighted match ranges (bold), dimmed parent path, optional kind/size. |
| `KeyMonitor.swift` | Local `NSEvent` monitor on the panel: ↑/↓ move selection, ⏎ open, ⌘⏎ reveal, Space Quick Look, ⌘C copy path, Esc hide. |
| `FileActions.swift` | Open (`NSWorkspace.open`), Reveal (`activateFileViewerSelecting`), Quick Look (`QLPreviewPanel`), Copy file + Copy path (`NSPasteboard`). |
| `IndexCoordinator.swift` | Owns `IndexStore`; on launch loads existing readers into `SearchService` (instant search on stale index), kicks background refresh; debounced reindex; exposes progress to menu bar. |
| `FSWatcher.swift` | `FSEventStreamCreate` over configured roots; coalesced callback → `SearchService.applyChange`; triggers debounced reindex. |
| `MenuBarController.swift` | `NSStatusItem` with menu: Show (hotkey hint), Reindex Now, Settings…, Quit. Shows indexing state. |
| `SettingsView.swift` + `AppConfig.swift` | SwiftUI settings window; `AppConfig` persists roots, hotkey (keyCode+modifiers), dock-icon toggle, max results to `UserDefaults`. |
| `PathReveal.swift` | Reconstruct a real (original-case) filesystem path from the index's lowercased path for actions — verify existence; if the lowercased path doesn't resolve, fall back to a case-insensitive directory walk. (Index stores lowercased bytes; the FS may be case-sensitive.) |

**Case-sensitivity note:** ClingCore lowercases paths in the blob. macOS default FS is case-insensitive, so the lowercased path usually opens fine, but actions must be robust. `PathReveal` resolves the true path: try the lowercased path as-is; if missing, walk parent dirs case-insensitively to recover original case. (A future ClingCore enhancement could store original-case paths in a side table; out of scope here.)

---

## 5. Memory & performance discipline

- Search runs off-main, debounced (60ms), with stale-result discard — the UI never blocks and a fast typist never piles up work.
- `maxResults` default 100 (configurable) — bounded result construction.
- On panel hide: call `adviseDontNeed()` on each root reader to release resident index pages, holding the app well under the <500MB ceiling when idle.
- Icons cached in a bounded `NSCache`; never decode full-res — request 32×32 thumbnails.
- The cached-delta-reader fix keeps typing smooth even with many live FS changes.

---

## 6. Build & packaging

`scripts/build-app.sh`:
1. `swift build -c release` (builds `ClingApp` executable + links ClingCore).
2. Assemble `ClingLite.app/Contents/{MacOS,Resources}`: copy binary; generate `Info.plist` (`LSUIElement=true`, `CFBundleIdentifier=com.clinglite.app`, version, `NSHumanReadableCopyright`); build icon `.icns` via `iconutil` from a generated iconset; ad-hoc `codesign --force --deep --sign -`.
3. Output `ClingLite.app` in repo root (gitignored).

`Package.swift` gains the `ClingApp` executable target (depends on ClingCore). swift-testing wrapper unchanged; the GUI smoke test is a runtime mode of the app binary, not a unit test.

---

## 7. Verification (definition of "fully verified")

1. **Headless unit tests** (swift-testing, via `scripts/test.sh`) for every ClingCore addition: `SearchService` (multi-root merge, change routing, base swap), `IndexStore` (loadOrBuild/reindex round-trip + manifest), cached-delta `LiveIndex` (no rebuild when delta unchanged; correct results after add/remove), `highlightRanges` (correct matched ranges).
2. **App smoke mode** (`ClingLite --smoke "<query>" --fixture <dir>`): boots NSApplication, builds a temp index over a known fixture tree, runs the query through the *real* SearchController→SearchService path, renders the results `SearchView` to a PNG via offscreen `NSHostingView` bitmap (no window-server dependency), asserts the expected file appears, writes the PNG, exits 0 (pass) / 1 (fail). This proves the full GUI render+search path programmatically.
3. **Live app verification:** `build-app.sh` then `open ClingLite.app`; trigger the panel (hotkey or `--show`); `screencapture` the panel and the menu-bar item; confirm visually. A first de-risking task confirms whether a visible window renders from this context; the offscreen-bitmap path (#2) is the authoritative fallback.
4. **Memory check:** launch the app, index a real tree, run searches, sample RSS via `currentResidentBytes()` / OS `time`; confirm well under 500MB and that hiding the panel releases pages.

---

## 8. Non-goals (Phase C)

Scripts engine, drag-to-zone accessibility grid, in-app syntax-highlighted code preview, quick-filters management UI, onboarding wizard, batch rename, external-volume management UI, auto-update/licensing.

---

## 9. Risks & mitigations

- **Window-server access from this execution context** — mitigated by the offscreen-bitmap smoke render (authoritative) plus a best-effort live screenshot; first task probes it explicitly.
- **Global hotkey needs no special permission** (Carbon RegisterEventHotKey works without Accessibility); verified at runtime.
- **Case-sensitivity of actions** — handled by `PathReveal` (§4).
- **FSEvents storms** — coalesced callback + debounced reindex; cached delta reader keeps per-search cost flat.
- **NSPanel focus/Spaces behavior** — standard `.nonactivatingPanel`/`canJoinAllSpaces` configuration; verified via live screenshot.
