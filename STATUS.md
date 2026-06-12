# ClingLite — Status

A memory-optimized reimplementation of [Cling](https://github.com/FuzzyIdeas/Cling)
(macOS instant fuzzy file finder). Goal: identical fast fuzzy search, **<500MB memory
no matter what**, no Xcode required, no paywall/telemetry.

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
