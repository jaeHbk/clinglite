# Attribution & Provenance

ClingLite is a memory-optimized, from-scratch reimplementation of **Cling**, the macOS
instant fuzzy file finder by FuzzyIdeas (Alin Panaitiu).

- Original project: https://github.com/FuzzyIdeas/Cling
- Original license: GPL-3.0

## What is derived from Cling

The fuzzy-scoring core in `Sources/ClingCore/Scoring/` (the fzf-style byte scorer, the
SIMD byte search, the 64-bit letter bitmask, the character-class / boundary-bonus tables,
and the scoring constants) was **ported closely from Cling's `SearchEngine.swift`**. Those
files carry inline comments noting the origin.

Because that code is derived from a GPL-3.0 work, **ClingLite as a whole is licensed under
GPL-3.0** (see `LICENSE`).

## What is original to ClingLite

Everything else was written from scratch for this project, including: the memory-mapped
structure-of-arrays index format, writer, and in-place reader; the multi-root
`SearchService`, persistent `IndexStore`, and base+delta `LiveIndex`; the `fts(3)` indexer
and ignore matcher; the `cling` CLI; and the entire SwiftUI/AppKit menu-bar app
(`Sources/ClingApp/`). The architectural goal — a hard <500MB memory ceiling regardless of
filesystem size, built with Command Line Tools only (no Xcode) — and its implementation are
original work.

This project is not affiliated with or endorsed by FuzzyIdeas.
