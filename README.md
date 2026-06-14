# ClingLite

A memory-optimized, native macOS **instant fuzzy file finder** — a Spotlight/Alfred-style
search panel that finds files across your disk in milliseconds while staying lightweight.

ClingLite is a from-scratch reimplementation of [Cling](https://github.com/FuzzyIdeas/Cling)
with one overriding goal: **a hard memory ceiling of <500MB regardless of filesystem size**,
where the original can use 1GB+. It is built with the macOS **Command Line Tools only — no
Xcode required** — and has **zero external dependencies** in its engine.

## Highlights

- **Fast fuzzy search** — fzf-style scoring over a memory-mapped index; sub-100ms searches.
- **Tiny memory footprint** — the index is memory-mapped and searched *in place* (clean,
  OS-evictable pages), so resident memory stays low. Real `~/Documents` (151k files):
  ~23MB while searching; a synthetic 2M-file index: ~80–100MB total / ~65ms per search.
- **Menu-bar agent** — summon a borderless search panel with a global hotkey (⌥Space).
- **Rich preview pane** — scrollable PDF (PDFKit), large image, or QuickLook thumbnail,
  plus Name / Path / Size / Date Modified.
- **Keyboard-first** — ↩ open, ⌘↩ reveal, ⌘Y Quick Look, ⌘T open in Terminal, ⌘R rename,
  ⌘C copy path, ⌘A select-all, arrows to navigate.
- **Live updates** — FSEvents keeps the index current; background reindexing.
- **CLI** — `cling index <root> <out.idx>` and `cling search <out.idx> <query…>`.

## Build & run

Requires macOS 14+ and the Command Line Tools (`xcode-select --install`). No Xcode.

```bash
# Run the test suite
./scripts/test.sh                 # debug
./scripts/test.sh -c release      # release (includes the memory-ceiling harness)

# Build the .app bundle (menu-bar agent)
./scripts/build-app.sh
open ClingLite.app                # then press ⌥Space to summon the panel

# Or use the CLI
swift build -c release
.build/release/cling index "$HOME" /tmp/home.idx
.build/release/cling search /tmp/home.idx report
```

## Architecture

- `Sources/ClingCore/` — the headless, fully-tested engine: memory-mapped structure-of-arrays
  index (format / writer / in-place reader), the ported fuzzy scorer, the `fts(3)` indexer,
  multi-root `SearchService`, persistent `IndexStore`, and base+delta `LiveIndex`.
- `Sources/ClingApp/` — the SwiftUI + AppKit menu-bar app (hotkey, panel, preview, actions,
  settings, FSEvents wiring).
- `Sources/cling/` — the command-line tool.

See `STATUS.md` for the detailed build log and verified numbers.

## License & attribution

ClingLite is licensed under **GPL-3.0** (see [`LICENSE`](LICENSE)). Its fuzzy-scoring core
is ported from [Cling](https://github.com/FuzzyIdeas/Cling) (GPL-3.0); everything else is
original. See [`NOTICE.md`](NOTICE.md) for full provenance. Not affiliated with FuzzyIdeas.
