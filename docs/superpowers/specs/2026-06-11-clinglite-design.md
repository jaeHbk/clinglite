# ClingLite — Design Spec

**Date:** 2026-06-11
**Goal:** A carbon-copy reimplementation of [Cling](https://github.com/FuzzyIdeas/Cling) (macOS instant fuzzy file finder) with a **hard memory ceiling of <500MB regardless of filesystem size**, equal or better speed (sub-100ms search, no lag), all features free, no telemetry, buildable without Xcode.

---

## 1. Context & root-cause analysis

Cling is a ~21.5K-LOC native Swift/SwiftUI+AppKit macOS app. It maintains an in-memory index of the filesystem to deliver fuzzy search results in under 100ms. Observed memory use is **1GB+**, with the upstream README itself quoting "300MB to 2GB."

Code analysis of the upstream repo (`/tmp/cling-upstream`, files `SearchEngine.swift`, `FuzzyClient.swift`, `VolumeIndex.swift`, et al.) pinned three root causes:

1. **mmap defeated by memcpy.** `SearchEngine.loadBinaryIndex` (`SearchEngine.swift:559–686`) `mmap`s the `.idx` file via `Data(contentsOf:options:.mappedIfSafe)` and then **immediately `memcpy`s every array into anonymous heap buffers** (lines 588–652, the largest copy being `allBytes` at 651–652). The result: the entire index is **dirty, non-reclaimable RAM**. The README claims the index is "marked swappable to disk" when backgrounded, but **no `madvise`/`vm_behavior`/`MADV_FREE` exists anywhere in the codebase** (verified by grep). The swappability feature is effectively not implemented.

2. **Paths stored twice.** Each file's path lives both as a Swift `String` in `Entry.path` (`SearchEngine.swift:376`, ~24B object overhead + UTF-8 bytes, ≈450MB for 9M files) **and** as lowercased bytes concatenated in `allBytes`. The `String` array is pure redundancy — search operates on bytes; paths are only needed for display of visible results.

3. **All scope engines resident simultaneously.** Home, Library, Applications, System, Root, plus per-volume engines are all loaded at init with no lazy-loading (`FuzzyClient`), ~150MB+ each → 750MB–1GB+ for a typical multi-scope setup.

**Per-file cost today:** ≈256 bytes → ≈256MB per 1M files, ≈2.3GB at 9M files.

### What is reusable (key de-risk)

`SearchEngine.swift` (the 2,879-line scoring heart) imports only `Foundation`, `simd`, `os.log` — **zero coupling to the private `Lowtech` framework**. The fuzzy scoring algorithm, SIMD byte search, bitmask filter, and parallel filter/score phases can be **reused nearly verbatim**. Only the *memory layout it reads from* and the *app/index glue* (`FuzzyClient.swift`, tangled in `Lowtech`/`ClopSDK`/`Ignore`/`Defaults`) need rewriting.

### Build environment (verified)

- Machine: Apple M3 Pro, 36GB RAM, macOS 26.5, **Command Line Tools only (no Xcode)**, Swift 6.3.2, arm64.
- CLT SDK ships `SwiftUI.framework` + `SwiftUI.swiftmodule` and `AppKit.framework`; `swiftc`, `actool`, `iconutil`, `codesign`, `plutil`, `sips` all present.
- **Conclusion:** a SwiftUI/AppKit `.app` can be compiled and bundled with CLT alone. No Xcode required.

---

## 2. Decisions (locked)

1. **Build:** CLT + SwiftPM, no Xcode. Clean rebuild as a Swift Package + hand-assembled `.app` bundle.
2. **Scope:** Strip paywall (Paddle), trial logic, Pro-gating, and telemetry (Sentry). **Every feature free.** Keep all real functionality.
3. **Memory:** **Hard ceiling at scale** — architect for a guaranteed RSS ceiling even at 9M+ files.

---

## 3. Core memory architecture (Approach A: mmap-in-place + structure-of-arrays)

### 3.1 Principle

Search **directly over a file-backed mmap**; never `memcpy` into heap. Pages are **clean and OS-evictable** under memory pressure, and only the pages actually touched fault in. Eliminate the `String` duplication entirely.

### 3.2 The access-pattern insight that guarantees the ceiling

The filter phase scans **only the `masks` array** for every file (`masks[i] & combinedMask == combinedMask`, `SearchEngine.swift:1681/1854`). Every other structure (basename masks, boundaries, path bytes, offsets, flags) is touched **only for the ~1–10% of files that survive the mask filter**. Therefore the *guaranteed hot working set* is just the `masks` region (+ `extIDs` when an extension filter is active); everything else faults in lazily and is evictable.

### 3.3 On-disk = in-memory layout (single mmap, structure-of-arrays)

One `.idx` file per scope/volume. A fixed header followed by contiguous columnar arrays, all naturally aligned so they can be read in place via `UnsafeRawPointer` slices:

```
Header:
  magic: UInt64, version: UInt32, entryCount: UInt64, blobBytes: UInt64,
  section offsets (one per column below)

Columns (length = entryCount each, except blob):
  masks        : UInt64   // letter bitmask  — HOT, scanned every query
  extIDs       : UInt16   // interned extension id — scanned when ext filter active
  bnMasks      : UInt64   // basename letter bitmask — candidates only
  bnBoundaries : UInt64   // word-boundary bits      — candidates only
  pathOffset   : UInt32   // offset into blob        — candidates only
  pathLen      : UInt16   // byte length in blob     — candidates only
  bnStart      : UInt16   // basename start offset    — candidates only
  flags        : UInt8    // isDir + segCount packed  — candidates only
  blob         : UInt8[]  // lowercased UTF-8 path bytes, concatenated
```

**No `path: String` column.** Display paths are reconstructed on demand from `blob[pathOffset ..< pathOffset+pathLen]` for the ~200 visible results only.

### 3.4 Resident budget (per index, 9M files)

| Column | Bytes/file | Access | Resident @ 9M |
|---|---|---|---|
| masks (U64) | 8 | every query | 72MB (hot) |
| extIDs (U16) | 2 | ext filter | 18MB |
| bnMasks (U64) | 8 | candidates | evictable |
| bnBoundaries (U64) | 8 | candidates | evictable |
| pathOffset (U32) | 4 | candidates | evictable |
| pathLen (U16) | 2 | candidates | evictable |
| bnStart (U16) | 2 | candidates | evictable |
| flags (U8) | 1 | candidates | evictable |
| blob | ~30–45 | candidates | evictable |

**Guaranteed hot working set ≈ 90MB** + faulted candidate pages + UI runtime. Comfortably **<500MB at 9M files actively searched**, far lower idle. On window hide we `madvise(MADV_DONTNEED)` / drop mappings to release pages.

### 3.5 Lazy per-scope loading

Engines are mmapped on first use, not all at init. Inactive scopes hold no resident pages. A scope toggled off `munmap`s.

### 3.6 Live updates: base + delta

The mmap'd base index is **read-only**. FSEvents-driven changes are handled by:
- a small **in-heap delta index** (same SoA columns, Swift arrays) holding recent adds/modifies — bounded by recent churn, so negligible heap cost;
- a **tombstone set** (`Set<UInt32>` of base entry ids, or path-hash set) for deletes/moves;
- search runs over **base (minus tombstones) ∪ delta**, merged by the existing multi-engine orchestration;
- a periodic/threshold re-index folds the delta into a fresh base `.idx` and clears delta+tombstones.

### 3.7 Optional compression (Phase 2, not required for ceiling)

Directory-interning: store each directory path once, files reference a `dirID`; reconstruct full path by concatenation. Cuts the blob ~40–60% (cold footprint + disk). Deferred because the ceiling is already met without it.

---

## 4. Search pipeline (reused, memory-adapted)

Algorithm stays **verbatim**; only the data source changes (mmap raw pointers instead of heap arrays; `Entry` carries offsets, not `String`).

1. **Parse** query into fuzzy tokens, extension tokens (`.png`, `*.mp4`), folder tokens (`in:/path`), dir-segment tokens (`foo/`), depth tokens (`depth:3`). NFD/NFC normalization. Compute `combinedMask = qMask | extMask | dirMask`.
2. **Phase 1 — Filter** (`DispatchQueue.concurrentPerform` across cores): 64-bit mask precheck over the hot `masks` region; O(1) `UInt16` extension-id compare; byte-level folder-prefix match; excluded-path set lookup. Candidate pool **capped at 50K** regardless of file count.
3. **Phase 2 — Score** (parallel): fzf-style `fuzzyScoreBytes` over candidate byte slices using `simdFindByte` (SIMD16 anchor search); multi-token independent scoring in non-overlapping regions; boundary/camelCase/consecutive bonuses.
4. **Merge/rank/dedup:** quality gate (top-third), composite rank (score, importance, prefix/basename match, depth), dedup by path, top-N.
5. **Multi-engine orchestration:** best engine first → instant interim results; remaining engines in parallel `TaskGroup`; final merge.

**Invariant preserved:** no per-query allocation scales with total file count (candidate pool fixed at 50K). This keeps both memory flat and latency sub-100ms.

**Indexer:** `fts_read` for local scopes, `FileManager` for external volumes; `.fsignore`/`.gitignore` honored via the `swift-ignore` package. Writes the §3.3 SoA format directly. Re-index ~every 3 days + manual.

---

## 5. App shell & UI

SwiftUI + AppKit hybrid built against the CLT SDK.

- **Scenes:** main window (`.hiddenTitleBar`, glass/vibrant/opaque appearance), Settings window (tabbed), first-run Onboarding.
- **Global hotkey:** first-party ~60-line Carbon `RegisterEventHotKey` wrapper (replaces private `Lowtech KM`). Configurable modifier+key.
- **Main UI:** search field with history (Up/Down cycle, Tab completion, Cmd+Down browse), filter picker (Quick Filters / Folder Filters / Volumes / All), results list (icon, name, path, size, date), action buttons row, right-click context menu, bottom status bar (reindex, count, activity log, settings).
- **File preview (memory-bounded by construction):**
  - Images: downsampled `CGImageSourceCreateThumbnailAtIndex` — never full-res decode.
  - Text: capped at 256KB (matches original).
  - PDF/Audio/Video: native views, lazily loaded, torn down on navigation away.
  - Archive listing via bundled `7zz`.
  - QuickLook fallback for unsupported types.
- **System integrations (reimplemented on raw APIs, no `Lowtech`):** FSEvents (`FSEventStreamCreate`), Full Disk Access detection, Accessibility drag-to-zone (`AXUIElement`), drag simulation (`NSDraggingSession`), CLI tool + IPC, shell integration, optional login item (`SMAppService`).

---

## 6. Dependencies

**Drop:** PaddleSPM, LowtechPro, AppReceiptValidator, ASN1Decoder (licensing); sentry-cocoa (telemetry); Sparkle (auto-update — personal build); Lowtech, LowtechIndie (private frameworks → replaced by small first-party wrappers); ClopSDK, Magnet, Sauce, DynamicColor, LaunchAtLogin, Defaults (→ thin `UserDefaults` helper).

**Keep:** `swift-ignore` (`.fsignore` parsing), `swift-argument-parser` (CLI).

**Phase-2 opt-in:** `HighlighterSwift` for syntax-highlighted code preview — pulls JavaScriptCore (memory cost), so Phase 1 uses plain monospaced text preview.

All Pro gates become no-ops; every feature available.

---

## 7. Build & packaging

- `Package.swift` (executable target) compiled with CLT `swiftc`.
- `scripts/build.sh` assembles the `.app`: `actool` (asset catalog), `plutil` (Info.plist with FDA/Accessibility usage strings + entitlements), `iconutil` (icon), ad-hoc `codesign` (sufficient for local use).
- **Project layout:**
  ```
  ~/Documents/clinglite/
    Package.swift
    Sources/ClingLite/{Engine,Index,UI,System,Actions,Preview}/
    Sources/clingcli/
    Resources/ (Assets.xcassets, Info.plist template, icon)
    scripts/build.sh
    Tests/ClingLiteTests/
    docs/superpowers/specs/
  ```

---

## 8. Verification (how we *prove* the ceiling)

- **Scorer parity tests:** known query→ranking fixtures to confirm the reused algorithm behaves identically.
- **Memory/RSS harness:** builds an index over a synthetic N-file tree (1M, 5M, 9M), runs representative searches, and **asserts resident set stays under the ceiling**. This is the gate that proves `<500MB`, not an assertion.
- **Latency harness:** asserts representative searches complete sub-100ms in a release build.
- **Manual app verification:** launch, hotkey, search, act-on-file, preview, background→foreground memory release.

---

## 9. Phasing

- **Phase 1 (core, usable app):** SoA mmap index + reused scorer + indexer; main window, search, results, file actions, global hotkey, FSEvents live updates (base+delta), filters, bounded preview, CLI. Fast, `<500MB`.
- **Phase 2 (long tail):** scripts engine, drag-to-zone AX grid, syntax-highlighted preview, directory-interning compression, onboarding/settings polish, optional login item.

---

## 10. Non-goals

- Not reproducing the paywall, trial, licensing, telemetry, or auto-updater.
- Not a complex-query/metadata search tool (same scope boundary as upstream Cling).
- Not Xcode-dependent.
