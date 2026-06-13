# ClingLite — Status

A memory-optimized reimplementation of [Cling](https://github.com/FuzzyIdeas/Cling)
(macOS instant fuzzy file finder). Goal: identical fast fuzzy search, **<500MB memory
no matter what**, no Xcode required, no paywall/telemetry.

## Plan B (GUI app) — ✅ COMPLETE & VERIFIED

A polished menu-bar agent (`ClingLite.app`, `LSUIElement`) summoned by a global hotkey
(⌥Space) as a borderless Spotlight-style panel, with live fuzzy results as you type,
keyboard nav, core file actions (Open / Reveal / Copy file / Copy path), background
indexing + FSEvents live updates, and a settings window. Built with Command Line Tools
only — no Xcode. Run `scripts/build-app.sh` to produce `ClingLite.app`.

**B1 — ClingCore orchestration** (headless, unit-tested): cached-delta `LiveIndex`,
`fuzzyHighlightRanges`, persistent per-root `IndexStore` (+ JSON manifest), multi-root
`SearchService`.

**B2 — ClingApp GUI**: `SearchController` (60 ms debounce, off-main, stale-discard),
`SearchView`/`RowView` (highlighted matches), `KeyablePanel` (focusable borderless
panel), Carbon `HotKey`, `FSWatcher`, `IndexCoordinator`, `MenuBarController`,
`SettingsView`, `PathResolver` (recovers true-case on-disk path from the lowercased index).

### Verified (real, OS-measured)

- **GUI render** (authoritative offscreen `NSHostingView`→PNG of the real `SearchView`
  via the real search path): renders the panel + highlighted `engine.swift` result row
  correctly in both debug and the shipping release binary.
- **Real `.app`**: launches as a menu-bar agent at **~38 MB idle**, **~117 MB peak**
  while background-indexing all of `$HOME` (1,072,733 files in ~47 s), **~55 MB on
  relaunch** from the cached index. Persistent index + manifest under
  `~/Library/Application Support/ClingLite/` confirmed; relaunch reuses it (instant start).
- **66 tests / 17 suites** green in debug + release. Memory-ceiling harness still holds
  (2 M files → 80 MB, 74 ms).
- `screencapture` of live windows is blocked in the build/automation context, so live
  windows are verified by the user running `ClingLite.app`; the offscreen render is the
  authoritative programmatic gate.

### Usability pass (post-launch fixes) — ✅

Three issues found by running the real app were root-caused and fixed:
1. **Autofocus** — the search field now takes keyboard focus on show (no click needed):
   `@FocusState` + `.focused()` driven by a focus tick the panel bumps each show.
2. **Results visible** — the live panel now **resizes to fit results** (was stuck at the
   search-bar height, clipping everything). `PanelLayout` is the single source of truth
   used by both the live window and the render harness, so they can't diverge again.
3. **Rich UI** — search bar + results list + **preview pane** (QuickLook thumbnail +
   Kind/Size/Modified/Where) + **hotkey footer** (Open / Reveal / Quick Look / Copy Path
   / Navigate / Close), matching the original's layout.

Added a `--ui-selftest` mode that drives the **real** `SearchPanel` and asserts on the
**live window** (height grew, rows present, field focused) — the verification the
original offscreen-only check lacked. Real app steady-state ~41 MB; preview shows real
QuickLook thumbnails. 72 tests / 19 suites green debug + release.

### Round 3 (feedback pass) — ✅

Investigated via a multi-agent workflow (4 parallel investigations → adversarial bug
verification → synthesis), then implemented + verified:
1. **Folder search** — folders matching a query now rank correctly. Root cause (verified
   by 2 independent skeptics): `isDir`/exact-name played no role in scoring, so an
   equal-scoring file with a shorter path buried the folder. Added a dir rank bonus
   (+scoreMatch, breaks ties) + exact-basename bonus (+scoreMatch×4, decisive).
2. **Preview metadata** — exactly four labeled rows: **Name, Path, Size, Date Modified**.
3. **Bigger preview + scrollable PDF** — panel 720→860 wide, preview 300→400, min content
   320→460; type-dispatched preview: `PDFPreview` (PDFKit `PDFView`, `.singlePageContinuous`
   = scrollable, verified live: page 1 + scrollbar over a 3-page doc), large image, or
   QuickLook thumbnail. (PDFView renders via a layer path that offscreen `cacheDisplay`
   can't capture — verified live via a window-ID `screencapture` instead.)
4. **Hotkeys** — **⌘T** opens the enclosing dir in Terminal.app; **⌘R** renames (NSAlert
   accessory field → `FileActions.rename` → `applyChange` + `controller.refresh()`).
   Footer now shows all 8 hints.

80 tests / 21 suites green debug + release; 2M harness holds (~101 MB, 64 ms).

### Round 3c (Edit menu) — ✅

The LSUIElement agent had no main menu, so macOS never routed standard text-editing
shortcuts to the search field — **⌘A did nothing**. Added `EditMenu` (App + Edit menu:
Undo/Redo, Cut, Copy, Paste, Delete, **Select All ⌘A**), installed at launch. Now ⌘A
selects the whole query and Delete clears it; ⌘X/⌘V/⌘Z also work. ⌘C stays "copy result
path" (the panel KeyMonitor owns it). 87 tests / 23 suites green.

### Phase C (deferred)

Full QuickLook *panel* (Space-to-peek; the inline preview pane shows thumbnails + scrollable
PDF), live hotkey re-binding UI, scripts engine, drag-to-zone accessibility grid, in-app
syntax-highlighted code preview, quick-filters management, onboarding wizard.

---

## Plan A (engine core) — ✅ COMPLETE & VERIFIED

The headless, fully-tested heart: fuzzy scorer, memory-mapped structure-of-arrays
index, filesystem indexer, base+delta live updates, and a `cling` CLI.

### Memory goal — PROVEN

Measured by the OS (`/usr/bin/time -l`), real filesystem (~/Documents, 151,749 files):

| Operation | Peak RSS | vs. original Cling (1GB+) |
|---|---|---|
| **Search** (151K-file index) | **23.4 MB** | ~45× smaller |
| **Index build** (151K files) | **100.4 MB** | — |

Synthetic 2M-file proof harness (release): **77 MB total process footprint, ~80 ms
avg search**. The mmap-in-place design means only touched pages fault in; the rest
stays OS-evictable. The `<500MB` ceiling holds with enormous headroom. Even a
pathological all-match query (every basename matches) stays bounded and adds only
~128 MB on top of the base.

### Speed

- 151K-file `~/Documents` indexed in **6.3 s**.
- Search over that index: **~18 ms** process-inclusive (mmap + parallel filter+score
  + print); the search itself is sub-millisecond.
- 70–90 ms on the 2M-file synthetic index (release).

### Search semantics (matches upstream Cling)

Fuzzy tokens match against the **basename** (the filename), so files *named* for the
query rank above incidental directory-path matches — e.g. `report` returns
`reporter.rs` / `report.md`, not `node_modules/.../istanbul-lib-report/...`. Directory
scoping is expressed explicitly via `in:<path>` and `seg/` tokens. This is also what
keeps broad queries fast: basenames are short, so the letter-mask prefilter is highly
selective.

### Tests

40 tests across 10 suites, green in both debug and release (`./scripts/test.sh`
and `./scripts/test.sh -c release`). Built with Command Line Tools only — no Xcode.
Includes regression tests for every issue found in the whole-implementation review
(corrupt-index safety, best-match survival on broad queries, unknown-extension
filtering, bounded pathological queries).

### What works (CLI)

```
cling index <root> <out.idx> [--ignore <patternsFile>]
cling search <out.idx> <query...>
```

Fuzzy matching, `.ext` extension filters, `in:<path>` folder scoping, `seg/`
directory-segment filters, and `depth:<n>` all functional.

## Known follow-ups (Phase 2)

- **Streaming IndexWriter:** the writer assembles the whole file in a heap `Data`
  buffer (transient peak ~306 MB at 2M entries). Fine through a few million files;
  stream to a `FileHandle` for 9M+.
- **Directory-interning compression** of the path blob (~40–60% smaller cold index).

## Next: Plan B — SwiftUI app shell

The GUI (window, global hotkey, results list, file actions, preview, settings,
onboarding, FSEvents wiring, `.app` bundle) wraps this verified `ClingCore` library.
To be planned against the real ClingCore API now that Plan A is proven.

## Plan B1 (ClingCore orchestration) — COMPLETE

Headless additions wrapping the Plan A engine for the GUI:
- Cached-delta `LiveIndex` (rebuild only on mutation, not per search)
- `fuzzyHighlightRanges` for result bolding
- Persistent per-root `IndexStore` (.idx + JSON manifest)
- Multi-root `SearchService` (merge/dedup/rank, FS-change routing by longest prefix, base swap)

56 tests / 13 suites green in debug + release. Still <500MB (2M-file harness: 78MB, 60ms).
