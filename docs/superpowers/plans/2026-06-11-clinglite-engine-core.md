# ClingLite Plan A — Search Engine Core + Index + CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless, fully-testable heart of ClingLite — the fuzzy search engine, the memory-mapped structure-of-arrays index, the filesystem indexer, base+delta live updates, a memory-ceiling proof harness, and a `cling` CLI — with a guaranteed <500MB resident ceiling at scale.

**Architecture:** Port Cling's proven byte-level fuzzy scorer verbatim (it imports only Foundation/simd/os.log). Replace its memory model: a single file-backed mmap per scope in columnar structure-of-arrays form, searched **in place** (clean, OS-evictable pages — never memcpy'd to heap), with **no path String column** (paths reconstructed from a byte blob only for visible results). Only the 8-byte `masks` column is scanned every query; everything else faults in for the ~1–10% of files surviving the mask filter. Live updates use an immutable base + a small in-heap delta + a tombstone set.

**Tech Stack:** Swift 6.3 / SwiftPM, Command Line Tools only (no Xcode). **Zero external dependencies** (hand-rolled CLI arg parsing + a minimal first-party ignore matcher) to honor the "super lightweight" mandate. `fts_read` (Darwin) for filesystem walking, `mmap`/`madvise` (Darwin) for the index.

> **Spec-refinement note (flag to user at handoff):** The spec §6 said "keep swift-ignore" and "keep swift-argument-parser". Plan A deliberately implements a minimal first-party `IgnoreMatcher` and hand-rolls CLI parsing so the engine core has **zero external dependencies** — maximally lightweight and hermetic (no network clones at build). swift-ignore / swift-argument-parser remain optional swaps if richer behavior is needed later.

> **⚠️ TESTING CONVENTION — READ FIRST (toolchain reality, overrides the test code blocks below):**
> Command Line Tools (no Xcode) **does not ship XCTest** (`import XCTest` → "no such module"). All test code in the tasks below is written in XCTest style for readability, but you MUST implement tests using **swift-testing** instead. Translate mechanically:
> - `import XCTest` → `import Testing`
> - `final class FooTests: XCTestCase { func testBar() {...} }` → `@Suite struct FooTests { @Test func bar() {...} }` (a throwing test: `@Test func bar() throws {...}`)
> - `XCTAssertEqual(a, b)` → `#expect(a == b)`; `XCTAssertNil(x)` → `#expect(x == nil)`; `XCTAssertNotNil`/unwrap → `let v = try #require(x)`; `XCTAssertGreaterThan(a, b)` → `#expect(a > b)`; `XCTAssertLessThan(a, b)` → `#expect(a < b)`; `XCTAssertLessThanOrEqual` → `#expect(a <= b)`; `XCTAssertGreaterThanOrEqual` → `#expect(a >= b)`; `XCTAssertTrue(x)` → `#expect(x)`; `XCTAssertFalse(x)` → `#expect(!x)`; the optional message arg becomes a trailing string in `#expect(cond, "msg")` only where supported, else drop it.
> - "append to the existing test file" → add `@Test` methods inside the existing `@Suite struct`.
> Run tests with the committed wrapper **`./scripts/test.sh [-c release] [FilterName]`** (it injects the CLT Testing.framework search/rpath/DYLD paths that plain `swift test` omits). Replace every `swift test --filter X` step with `./scripts/test.sh X`, and `swift test` with `./scripts/test.sh`. The fail-first → pass verification discipline still applies.

---

## File Structure

```
~/Documents/clinglite/
  Package.swift                              # lib ClingCore + exec cling + test target
  Sources/
    ClingCore/
      Scoring/
        CharTables.swift     # scoring constants, CC enum, ccTable, bonusFlat
        Masks.swift          # letterMaskBytes (64-bit letter bitmask)
        SIMDSearch.swift     # simdFindByte (SIMD16 anchor search)
        FuzzyScorer.swift    # fuzzyScoreBytes (fzf-style alignment scorer)
      Index/
        IndexFormat.swift    # header layout, magic/version, flag packing
        RawEntry.swift       # in-memory entry produced by the walker
        IndexWriter.swift    # build .idx (SoA columns + blob + ext table)
        IndexReader.swift    # mmap-in-place reader; typed column pointers
      Indexer/
        IgnoreMatcher.swift  # minimal .fsignore/.gitignore glob matcher
        FileWalker.swift     # fts_read recursive walk -> RawEntry stream
        Indexer.swift        # orchestrate walk -> IndexWriter
      Engine/
        QueryParser.swift    # parse query into typed tokens + masks
        SearchEngine.swift   # filter+score over reader; merge/rank/dedup
        Delta.swift          # base + in-heap delta + tombstone search merge
        Memory.swift         # madvise/munmap helpers
      ClingCore.swift        # umbrella: public Engine facade
    cling/
      main.swift             # hand-rolled CLI: `cling index` / `cling search`
  Tests/
    ClingCoreTests/
      ScorerTests.swift
      MaskTests.swift
      IndexRoundTripTests.swift
      QueryParserTests.swift
      SearchTests.swift
      IndexerTests.swift
      DeltaTests.swift
      MemoryHarnessTests.swift
      CLITests.swift
```

Each file has one responsibility. `ClingCore` is a library target; `cling` is an executable that links it; tests exercise the library and the CLI binary.

---

## Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClingCore/ClingCore.swift`
- Create: `Sources/cling/main.swift`
- Create: `Tests/ClingCoreTests/ScaffoldTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClingLite",
    platforms: [.macOS(.v14)], // v14: CLT Testing.framework is built for macOS 14; avoids linker version warning
    products: [
        .library(name: "ClingCore", targets: ["ClingCore"]),
        .executable(name: "cling", targets: ["cling"]),
    ],
    targets: [
        .target(
            name: "ClingCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "cling", dependencies: ["ClingCore"]),
        .testTarget(name: "ClingCoreTests", dependencies: ["ClingCore"]),
    ]
)
```

- [ ] **Step 2: Write the umbrella file with a version constant**

`Sources/ClingCore/ClingCore.swift`:

```swift
import Foundation

public enum ClingCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write a minimal CLI entry point**

`Sources/cling/main.swift`:

```swift
import ClingCore
import Foundation

// Real argument handling arrives in Task 17. For scaffolding, just prove linkage.
print("cling \(ClingCore.version)")
```

- [ ] **Step 4: Write the scaffold test**

`Tests/ClingCoreTests/ScaffoldTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class ScaffoldTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertFalse(ClingCore.version.isEmpty)
    }
}
```

- [ ] **Step 5: Run build + tests, verify pass**

Run: `cd ~/Documents/clinglite && swift build && swift test`
Expected: build succeeds; `testVersionPresent` PASSES.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/clinglite
git add Package.swift Sources Tests
git commit -m "chore: scaffold ClingCore library, cling executable, test target"
```

---

## Task 2: Character tables and scoring constants

**Files:**
- Create: `Sources/ClingCore/Scoring/CharTables.swift`
- Test: `Tests/ClingCoreTests/MaskTests.swift` (shared with Task 3; create here)

This ports Cling's scoring tables verbatim (`SearchEngine.swift:14-131`). They are module-internal.

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/MaskTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class MaskTests: XCTestCase {
    func testCharClassTable() {
        XCTAssertEqual(ccTable[Int(UInt8(ascii: "a"))], .lower)
        XCTAssertEqual(ccTable[Int(UInt8(ascii: "Z"))], .upper)
        XCTAssertEqual(ccTable[Int(UInt8(ascii: "5"))], .number)
        XCTAssertEqual(ccTable[Int(UInt8(ascii: "/"))], .delim)
        XCTAssertEqual(ccTable[Int(UInt8(ascii: " "))], .white)
    }

    func testBonusFlatCamel() {
        // lower -> upper is a camelCase boundary (positive bonus)
        XCTAssertGreaterThan(bonusFlat[CC.lower.rawValue * ccCount + CC.upper.rawValue], 0)
    }
}
```

- [ ] **Step 2: Run, verify it fails to compile**

Run: `swift test --filter MaskTests`
Expected: FAIL — `ccTable`/`CC`/`bonusFlat` undefined.

- [ ] **Step 3: Implement `CharTables.swift`**

```swift
import Foundation

// Scoring constants (ported from Cling SearchEngine.swift; tuned fzf-style weights).
let scoreMatch = 16
let gapStart = -3
let gapExtend = -1
let bonusBoundary = 8
let bonusConsec = 4
let firstCharMul = 2

// Boundary bonus variants used by bonusFlat.
let bonusBdWhite = 10
let bonusBdDelim = 9
let bonusCamel123 = 7
let bonusNonWord = 6

enum CC: Int { case white = 0, nonWord, delim, lower, upper, letter, number }
let ccCount = 7

let ccTable: [CC] = {
    var t = [CC](repeating: .nonWord, count: 256)
    for i in 0x61 ... 0x7A { t[i] = .lower }   // a-z
    for i in 0x41 ... 0x5A { t[i] = .upper }   // A-Z
    for i in 0x30 ... 0x39 { t[i] = .number }  // 0-9
    for v: Int in [0x09, 0x0A, 0x0D, 0x20] { t[v] = .white }
    for v: Int in [0x2F, 0x2D, 0x5F, 0x2E, 0x2C, 0x3A, 0x3B, 0x7C] { t[v] = .delim }
    return t
}()

private func buildBonusFlat() -> [Int] {
    func b(_ p: CC, _ c: CC) -> Int {
        if c.rawValue > CC.nonWord.rawValue {
            switch p {
            case .white: return bonusBdWhite
            case .delim: return bonusBdDelim
            case .nonWord: return bonusBoundary
            default: break
            }
        }
        if p == .lower, c == .upper { return bonusCamel123 }
        if p != .number, c == .number { return bonusCamel123 }
        switch c {
        case .nonWord, .delim: return bonusNonWord
        case .white: return bonusBdWhite
        default: return 0
        }
    }
    var m = [Int](repeating: 0, count: ccCount * ccCount)
    for p in 0 ..< ccCount {
        for c in 0 ..< ccCount {
            m[p * ccCount + c] = b(CC(rawValue: p)!, CC(rawValue: c)!)
        }
    }
    return m
}

let bonusFlat: [Int] = buildBonusFlat()
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter MaskTests`
Expected: `testCharClassTable` PASS; `testBonusFlatCamel` PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Scoring/CharTables.swift Tests/ClingCoreTests/MaskTests.swift
git commit -m "feat: port scoring constants, char-class table, bonus matrix"
```

---

## Task 3: Letter bitmask

**Files:**
- Create: `Sources/ClingCore/Scoring/Masks.swift`
- Test: append to `Tests/ClingCoreTests/MaskTests.swift`

- [ ] **Step 1: Add the failing test** to `MaskTests`:

```swift
    func testLetterMask() {
        let bytes = Array("ab.".utf8)
        let m = bytes.withUnsafeBufferPointer { letterMaskBytes($0) }
        // bit0 = 'a', bit1 = 'b', bit36 = '.'
        XCTAssertEqual(m, (1 << 0) | (1 << 1) | (1 << 36))
    }

    func testMaskSupersetProperty() {
        // A query mask must be a subset of any text mask that contains all query letters.
        let q = Array("abc".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        let t = Array("xabcz".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        XCTAssertEqual(t & q, q)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter MaskTests/testLetterMask`
Expected: FAIL — `letterMaskBytes` undefined.

- [ ] **Step 3: Implement `Masks.swift`** (verbatim from `SearchEngine.swift:323-335`):

```swift
import Foundation

/// 64-bit presence bitmask: a-z -> bits 0..25, 0-9 -> bits 26..35, '.' 36, '-' 37, '_' 38.
@inline(__always)
func letterMaskBytes(_ p: UnsafeBufferPointer<UInt8>) -> UInt64 {
    var m: UInt64 = 0
    for i in 0 ..< p.count {
        let v = p[i]
        if v >= 0x61, v <= 0x7A { m |= 1 << UInt64(v &- 0x61) }
        else if v >= 0x30, v <= 0x39 { m |= 1 << UInt64(26 &+ v &- 0x30) }
        else if v == 0x2E { m |= 1 << 36 }
        else if v == 0x2D { m |= 1 << 37 }
        else if v == 0x5F { m |= 1 << 38 }
    }
    return m
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter MaskTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Scoring/Masks.swift Tests/ClingCoreTests/MaskTests.swift
git commit -m "feat: port 64-bit letter bitmask"
```

---

## Task 4: SIMD byte search

**Files:**
- Create: `Sources/ClingCore/Scoring/SIMDSearch.swift`
- Test: `Tests/ClingCoreTests/ScorerTests.swift` (create; shared with Task 5)

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/ScorerTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class ScorerTests: XCTestCase {
    func testSimdFindByte() {
        let s = Array("the quick brown fox jumps over the lazy dog".utf8)
        s.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            XCTAssertEqual(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "q"), from: 0), 4)
            XCTAssertEqual(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "z"), from: 0), 37)
            XCTAssertEqual(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "X"), from: 0), -1)
            // from beyond a match returns the next occurrence
            XCTAssertEqual(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "t"), from: 1), 31)
        }
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter ScorerTests/testSimdFindByte`
Expected: FAIL — `simdFindByte` undefined.

- [ ] **Step 3: Implement `SIMDSearch.swift`** (verbatim from `SearchEngine.swift:137-157`):

```swift
import simd

/// First occurrence of `needle` at or after `from`, scanning 16 bytes at a time. -1 if absent.
@inline(__always)
func simdFindByte(_ base: UnsafePointer<UInt8>, count: Int, needle: UInt8, from: Int) -> Int {
    let needleVec = SIMD16<UInt8>(repeating: needle)
    var i = from
    while i &+ 16 <= count {
        let block = UnsafeRawPointer(base + i).loadUnaligned(as: SIMD16<UInt8>.self)
        let cmp = block .== needleVec
        var lane = 0
        while lane < 16 {
            if cmp[lane] { return i &+ lane }
            lane &+= 1
        }
        i &+= 16
    }
    while i < count {
        if base[i] == needle { return i }
        i &+= 1
    }
    return -1
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter ScorerTests/testSimdFindByte`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Scoring/SIMDSearch.swift Tests/ClingCoreTests/ScorerTests.swift
git commit -m "feat: port SIMD16 byte search"
```

---

## Task 5: Fuzzy scorer

**Files:**
- Create: `Sources/ClingCore/Scoring/FuzzyScorer.swift`
- Test: append to `Tests/ClingCoreTests/ScorerTests.swift`

- [ ] **Step 1: Add failing tests** to `ScorerTests`:

```swift
    private func score(_ pat: String, _ txt: String) -> Int? {
        let p = Array(pat.utf8), t = Array(txt.utf8)
        return p.withUnsafeBufferPointer { pb in
            t.withUnsafeBufferPointer { tb in
                fuzzyScoreBytes(pb, tb)?.score
            }
        }
    }

    func testEmptyPatternScoresZero() {
        XCTAssertEqual(score("", "anything"), 0)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(score("xyz", "abc"))
    }

    func testAnchorEnumerationPrefersTighterSegment() {
        // "lnr" should score higher inside "lunar" (single segment, boundary-aligned)
        // than scattered across "alin/.../lunar". Both contain l,n,r in order.
        let tight = score("lnr", "lunar")!
        let scattered = score("lnr", "alintnr")!  // l(in alin), n, r scattered
        XCTAssertGreaterThan(tight, scattered)
    }

    func testConsecutiveBeatsGapped() {
        XCTAssertGreaterThan(score("abc", "abc")!, score("abc", "axbxc")!)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter ScorerTests`
Expected: FAIL — `fuzzyScoreBytes` undefined.

- [ ] **Step 3: Implement `FuzzyScorer.swift`** (verbatim from `SearchEngine.swift:210-319`):

```swift
import Foundation

@inline(__always) func toLowerByte(_ b: UInt8) -> UInt8 { (b >= 0x41 && b <= 0x5A) ? b &+ 32 : b }

/// fzf-style alignment scorer over raw bytes. Returns best (score, start, end) or nil if no match.
/// `boundaries`/`boundariesOffset` carry precomputed camelCase/delimiter boundary bits for the
/// text region so bonuses survive lowercasing.
func fuzzyScoreBytes(
    _ pat: UnsafeBufferPointer<UInt8>,
    _ txt: UnsafeBufferPointer<UInt8>,
    boundaries: UInt64 = 0,
    boundariesOffset: Int = 0
) -> (score: Int, start: Int, end: Int)? {
    let M = pat.count, N = txt.count
    if M == 0 { return (0, 0, 0) }
    if M > N { return nil }

    let txtBase = txt.baseAddress!
    let firstChar = pat[0]

    var bestScore = Int.min
    var bestStart = -1
    var bestEnd = -1

    var anchorFrom = 0
    var anchorsTried = 0
    let maxAnchors = 32

    while anchorsTried < maxAnchors {
        let anchor = simdFindByte(txtBase, count: N, needle: firstChar, from: anchorFrom)
        if anchor < 0 { break }
        if anchor &+ M > N { break }

        var pi = 1
        var searchFrom = anchor &+ 1
        var lastPos = anchor
        var matched = true
        while pi < M {
            let pos = simdFindByte(txtBase, count: N, needle: pat[pi], from: searchFrom)
            if pos < 0 { matched = false; break }
            lastPos = pos
            searchFrom = pos &+ 1
            pi &+= 1
        }
        if !matched { break }

        let eidx = lastPos &+ 1
        var sidx = anchor

        pi = M &- 1
        var bi = eidx &- 1
        while bi >= anchor {
            if txtBase[bi] == pat[pi] {
                pi &-= 1
                if pi < 0 { sidx = bi; break }
            }
            bi &-= 1
        }

        var score = 0, consecutive = 0, firstBonus = 0, inGap = false
        var prevCC = sidx > 0 ? ccTable[Int(txt[sidx &- 1])].rawValue : CC.delim.rawValue
        pi = 0
        for i in sidx ..< eidx {
            let b = txt[i]
            let curCC = ccTable[Int(b)].rawValue
            if toLowerByte(b) == pat[pi] {
                score &+= scoreMatch
                var bonus = bonusFlat[prevCC &* ccCount &+ curCC]
                if boundaries != 0 {
                    let bpos = i &- boundariesOffset
                    if bpos >= 0, bpos < 64, boundaries & (1 << UInt64(bpos)) != 0 {
                        bonus = max(bonus, bonusBoundary)
                    }
                }
                if consecutive == 0 {
                    firstBonus = bonus
                } else {
                    if bonus >= bonusBoundary, bonus > firstBonus { firstBonus = bonus }
                    bonus = max(bonus, max(bonusConsec, firstBonus))
                }
                score &+= pi == 0 ? bonus &* firstCharMul : bonus
                inGap = false; consecutive &+= 1; pi &+= 1
            } else {
                score &+= inGap ? gapExtend : gapStart
                inGap = true; consecutive = 0; firstBonus = 0
            }
            prevCC = curCC
        }

        if score > bestScore {
            bestScore = score
            bestStart = sidx
            bestEnd = eidx
        }

        anchorFrom = anchor &+ 1
        anchorsTried &+= 1
    }

    return bestStart < 0 ? nil : (bestScore, bestStart, bestEnd)
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter ScorerTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Scoring/FuzzyScorer.swift Tests/ClingCoreTests/ScorerTests.swift
git commit -m "feat: port fzf-style byte fuzzy scorer with anchor enumeration"
```

---

## Task 6: Index format

**Files:**
- Create: `Sources/ClingCore/Index/IndexFormat.swift`
- Test: `Tests/ClingCoreTests/IndexRoundTripTests.swift` (create; shared with Tasks 7-8)

The header is a fixed 128-byte little-endian block with explicit section offsets so the reader is version-tolerant.

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/IndexRoundTripTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class IndexRoundTripTests: XCTestCase {
    func testHeaderConstants() {
        XCTAssertEqual(IndexFormat.headerSize, 128)
        XCTAssertEqual(IndexFormat.magic, 0x434C_4E47_4C49_5431) // "CLNGLIT1"
        XCTAssertEqual(IndexFormat.version, 1)
    }

    func testFlagPacking() {
        let f = IndexFormat.packFlags(isDir: true, segCount: 5)
        XCTAssertTrue(IndexFormat.isDir(f))
        XCTAssertEqual(IndexFormat.segCount(f), 5)
        let g = IndexFormat.packFlags(isDir: false, segCount: 200) // clamps to 127
        XCTAssertFalse(IndexFormat.isDir(g))
        XCTAssertEqual(IndexFormat.segCount(g), 127)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexRoundTripTests/testHeaderConstants`
Expected: FAIL — `IndexFormat` undefined.

- [ ] **Step 3: Implement `IndexFormat.swift`**

```swift
import Foundation

/// On-disk = in-memory columnar layout. All little-endian. Header is 128 bytes.
///
/// Header field offsets (bytes):
///   0  magic UInt64        | 8  version UInt32 | 12 flags UInt32
///   16 entryCount UInt64   | 24 blobBytes UInt64
///   32 off_masks UInt64    | 40 off_bnMasks UInt64   | 48 off_bnBoundaries UInt64
///   56 off_pathOffset U64  | 64 off_pathLen U64      | 72 off_bnStart U64
///   80 off_extIDs U64      | 88 off_flags U64        | 96 off_blob U64
///   104 off_extTable U64   | 112..127 reserved
///
/// Columns (length = entryCount): masks U64, bnMasks U64, bnBoundaries U64,
///   pathOffset U32, pathLen U16, bnStart U16, extIDs U16, flags U8.
/// Blob: concatenated lowercased UTF-8 path bytes.
/// Ext table: extCount U32, then for each ext: len U8 + raw bytes (id == index).
enum IndexFormat {
    static let magic: UInt64 = 0x434C_4E47_4C49_5431 // 'C''L''N''G''L''I''T''1'
    static let version: UInt32 = 1
    static let headerSize = 128

    // Header field byte offsets.
    static let offMagic = 0, offVersion = 8, offFlags = 12
    static let offEntryCount = 16, offBlobBytes = 24
    static let offMasksOff = 32, offBnMasksOff = 40, offBnBoundsOff = 48
    static let offPathOffOff = 56, offPathLenOff = 64, offBnStartOff = 72
    static let offExtIDsOff = 80, offFlagsOff = 88, offBlobOff = 96, offExtTableOff = 104

    @inline(__always) static func packFlags(isDir: Bool, segCount: Int) -> UInt8 {
        let s = UInt8(min(max(segCount, 0), 127))
        return s | (isDir ? 0x80 : 0)
    }
    @inline(__always) static func isDir(_ f: UInt8) -> Bool { f & 0x80 != 0 }
    @inline(__always) static func segCount(_ f: UInt8) -> Int { Int(f & 0x7F) }

    /// 8-byte alignment helper used by the writer to place sections.
    @inline(__always) static func align8(_ n: Int) -> Int { (n + 7) & ~7 }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter IndexRoundTripTests/testHeaderConstants IndexRoundTripTests/testFlagPacking`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Index/IndexFormat.swift Tests/ClingCoreTests/IndexRoundTripTests.swift
git commit -m "feat: define columnar mmap index format + flag packing"
```

---

## Task 7: Raw entry + index writer

**Files:**
- Create: `Sources/ClingCore/Index/RawEntry.swift`
- Create: `Sources/ClingCore/Index/IndexWriter.swift`
- Test: append to `Tests/ClingCoreTests/IndexRoundTripTests.swift`

`RawEntry` is what the walker produces; `IndexWriter` derives all columns (masks, basename info, ext interning) and writes the file. The writer is the **only** place lowercasing, mask computation, and ext interning happen.

- [ ] **Step 1: Add the failing test** to `IndexRoundTripTests`:

```swift
    func testWriterProducesValidHeader() throws {
        let entries = [
            RawEntry(path: "/Users/me/Documents/report.pdf", isDir: false),
            RawEntry(path: "/Users/me/Pictures", isDir: true),
            RawEntry(path: "/Users/me/Code/main.swift", isDir: false),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t1.idx")
        try? FileManager.default.removeItem(at: url)
        try IndexWriter.write(entries: entries, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, IndexFormat.headerSize)
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self) }
        XCTAssertEqual(magic, IndexFormat.magic)
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) }
        XCTAssertEqual(count, 3)
        try? FileManager.default.removeItem(at: url)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexRoundTripTests/testWriterProducesValidHeader`
Expected: FAIL — `RawEntry`/`IndexWriter` undefined.

- [ ] **Step 3: Implement `RawEntry.swift`**

```swift
import Foundation

/// Minimal record produced by the filesystem walker, consumed by the writer.
public struct RawEntry {
    public let path: String
    public let isDir: Bool
    public init(path: String, isDir: Bool) {
        self.path = path
        self.isDir = isDir
    }
}
```

- [ ] **Step 4: Implement `IndexWriter.swift`**

```swift
import Foundation

/// Builds the columnar .idx from RawEntry values: lowercases path bytes into the blob,
/// computes letter masks, basename masks, word-boundary bits, basename offsets, extension IDs.
public enum IndexWriter {
    /// Word-boundary detection over a lowercased basename's *original-cased* bytes.
    /// Sets bit at each position that begins a word (start, after delimiter/space,
    /// lower->upper camelCase, non-number->number). Mirrors Cling's boundary logic.
    private static func basenameBoundaries(_ orig: ArraySlice<UInt8>) -> UInt64 {
        var bits: UInt64 = 0
        var pos = 0
        var prev = CC.delim
        for b in orig {
            if pos >= 64 { break }
            let cur = ccTable[Int(b)]
            let isBoundary = pos == 0
                || (prev == .lower && cur == .upper)
                || prev == .delim || prev == .white || prev == .nonWord
                || (prev != .number && cur == .number)
            if isBoundary { bits |= 1 << UInt64(pos) }
            prev = cur
            pos &+= 1
        }
        return bits
    }

    public static func write(entries: [RawEntry], to url: URL) throws {
        let n = entries.count

        var masks = [UInt64](repeating: 0, count: n)
        var bnMasks = [UInt64](repeating: 0, count: n)
        var bnBounds = [UInt64](repeating: 0, count: n)
        var pathOff = [UInt32](repeating: 0, count: n)
        var pathLen = [UInt16](repeating: 0, count: n)
        var bnStart = [UInt16](repeating: 0, count: n)
        var extIDs = [UInt16](repeating: 0, count: n)
        var flags = [UInt8](repeating: 0, count: n)
        var blob = [UInt8](); blob.reserveCapacity(n * 48)

        var extToID = [String: UInt16]()
        var extList = [String]()  // id == index

        for i in 0 ..< n {
            let e = entries[i]
            let orig = Array(e.path.utf8)
            // Lowercased copy for the blob and masks.
            var lc = orig
            for j in 0 ..< lc.count { lc[j] = toLowerByte(lc[j]) }

            let off = blob.count
            blob.append(contentsOf: lc)
            pathOff[i] = UInt32(truncatingIfNeeded: off)
            pathLen[i] = UInt16(truncatingIfNeeded: min(lc.count, 0xFFFF))

            // Basename = bytes after the last '/'.
            var bn = 0
            var k = lc.count - 1
            while k >= 0 { if lc[k] == 0x2F { bn = k + 1; break }; k -= 1 }
            bnStart[i] = UInt16(truncatingIfNeeded: min(bn, 0xFFFF))

            masks[i] = lc.withUnsafeBufferPointer { letterMaskBytes($0) }
            bnMasks[i] = lc[bn...].withUnsafeBufferPointer { letterMaskBytes($0) }
            bnBounds[i] = basenameBoundaries(orig[bn...])

            // Extension = bytes after the last '.' in the basename (no dot -> id 0).
            var extID: UInt16 = 0
            if let dot = lc[bn...].lastIndex(of: 0x2E), dot + 1 < lc.count {
                let ext = String(decoding: lc[(dot + 1)...], as: UTF8.self)
                if let id = extToID[ext] { extID = id }
                else {
                    let id = UInt16(extList.count + 1) // 0 reserved for "no ext"
                    extToID[ext] = id; extList.append(ext); extID = id
                }
            }
            extIDs[i] = extID

            flags[i] = IndexFormat.packFlags(isDir: e.isDir, segCount: lc.reduce(0) { $0 + ($1 == 0x2F ? 1 : 0) })
        }

        // Assemble file: header + 8-aligned sections + blob + ext table.
        var out = Data()
        func appendArray<T>(_ a: [T]) { a.withUnsafeBytes { out.append(contentsOf: $0) } }
        func pad8() { while out.count % 8 != 0 { out.append(0) } }

        out.append(Data(count: IndexFormat.headerSize)) // placeholder header, patched below

        let offMasks = out.count;      appendArray(masks);      pad8()
        let offBnMasks = out.count;    appendArray(bnMasks);    pad8()
        let offBnBounds = out.count;   appendArray(bnBounds);   pad8()
        let offPathOff = out.count;    appendArray(pathOff);    pad8()
        let offPathLen = out.count;    appendArray(pathLen);    pad8()
        let offBnStart = out.count;    appendArray(bnStart);    pad8()
        let offExtIDs = out.count;     appendArray(extIDs);     pad8()
        let offFlags = out.count;      appendArray(flags);      pad8()
        let offBlob = out.count;       out.append(contentsOf: blob); pad8()

        let offExtTable = out.count
        var extCount = UInt32(extList.count)
        withUnsafeBytes(of: &extCount) { out.append(contentsOf: $0) }
        for ext in extList {
            let b = Array(ext.utf8)
            out.append(UInt8(truncatingIfNeeded: min(b.count, 255)))
            out.append(contentsOf: b.prefix(255))
        }

        // Patch header.
        func putU64(_ v: UInt64, at o: Int) { var x = v; withUnsafeBytes(of: &x) { out.replaceSubrange(o ..< o+8, with: $0) } }
        func putU32(_ v: UInt32, at o: Int) { var x = v; withUnsafeBytes(of: &x) { out.replaceSubrange(o ..< o+4, with: $0) } }
        putU64(IndexFormat.magic, at: IndexFormat.offMagic)
        putU32(IndexFormat.version, at: IndexFormat.offVersion)
        putU32(0, at: IndexFormat.offFlags)
        putU64(UInt64(n), at: IndexFormat.offEntryCount)
        putU64(UInt64(blob.count), at: IndexFormat.offBlobBytes)
        putU64(UInt64(offMasks), at: IndexFormat.offMasksOff)
        putU64(UInt64(offBnMasks), at: IndexFormat.offBnMasksOff)
        putU64(UInt64(offBnBounds), at: IndexFormat.offBnBoundsOff)
        putU64(UInt64(offPathOff), at: IndexFormat.offPathOffOff)
        putU64(UInt64(offPathLen), at: IndexFormat.offPathLenOff)
        putU64(UInt64(offBnStart), at: IndexFormat.offBnStartOff)
        putU64(UInt64(offExtIDs), at: IndexFormat.offExtIDsOff)
        putU64(UInt64(offFlags), at: IndexFormat.offFlagsOff)
        putU64(UInt64(offBlob), at: IndexFormat.offBlobOff)
        putU64(UInt64(offExtTable), at: IndexFormat.offExtTableOff)

        try out.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Run, verify pass**

Run: `swift test --filter IndexRoundTripTests/testWriterProducesValidHeader`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClingCore/Index/RawEntry.swift Sources/ClingCore/Index/IndexWriter.swift Tests/ClingCoreTests/IndexRoundTripTests.swift
git commit -m "feat: index writer building columnar SoA index from raw entries"
```

---

## Task 8: Memory-mapped index reader

**Files:**
- Create: `Sources/ClingCore/Index/IndexReader.swift`
- Test: append to `Tests/ClingCoreTests/IndexRoundTripTests.swift`

The reader `mmap`s the file read-only and exposes **typed pointers into the mapping** — no copying. It reconstructs a path String only on demand.

- [ ] **Step 1: Add the failing test** to `IndexRoundTripTests`:

```swift
    func testReaderRoundTrip() throws {
        let entries = [
            RawEntry(path: "/Users/me/Documents/report.pdf", isDir: false),
            RawEntry(path: "/Users/me/Pictures", isDir: true),
            RawEntry(path: "/Users/me/Code/Main.swift", isDir: false),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2.idx")
        try? FileManager.default.removeItem(at: url)
        try IndexWriter.write(entries: entries, to: url)

        let r = try IndexReader(url: url)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.path(2), "/users/me/code/main.swift")        // blob is lowercased
        XCTAssertTrue(IndexFormat.isDir(r.flags[1]))
        // 'report.pdf' mask must contain letters r,e,p,o,t,d,f and '.'
        let q = Array("rpt".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        XCTAssertEqual(r.masks[0] & q, q)
        // ext resolution: ".pdf" should resolve to the id stored on entry 0
        XCTAssertEqual(r.extID(forExtension: "pdf"), r.extIDs[0])
        try? FileManager.default.removeItem(at: url)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexRoundTripTests/testReaderRoundTrip`
Expected: FAIL — `IndexReader` undefined.

- [ ] **Step 3: Implement `IndexReader.swift`**

```swift
import Foundation

public enum IndexError: Error { case open, badMagic, badVersion, truncated }

/// Read-only memory-mapped view over a .idx file. Columns are typed pointers into the mapping;
/// nothing is copied to the heap. Pages fault in on first touch and are OS-evictable.
public final class IndexReader {
    private let base: UnsafeRawPointer
    public let byteCount: Int
    public let count: Int
    public let blobBytes: Int

    public let masks: UnsafePointer<UInt64>
    public let bnMasks: UnsafePointer<UInt64>
    public let bnBoundaries: UnsafePointer<UInt64>
    public let pathOffset: UnsafePointer<UInt32>
    public let pathLen: UnsafePointer<UInt16>
    public let bnStart: UnsafePointer<UInt16>
    public let extIDs: UnsafePointer<UInt16>
    public let flags: UnsafePointer<UInt8>
    public let blob: UnsafePointer<UInt8>

    private var extDict: [String: UInt16] = [:]

    public init(url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        if fd < 0 { throw IndexError.open }
        defer { close(fd) }
        var st = stat()
        if fstat(fd, &st) != 0 { throw IndexError.open }
        let size = Int(st.st_size)
        if size < IndexFormat.headerSize { throw IndexError.truncated }
        guard let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), p != MAP_FAILED else { throw IndexError.open }
        self.base = UnsafeRawPointer(p)
        self.byteCount = size

        func u64(_ o: Int) -> UInt64 { base.loadUnaligned(fromByteOffset: o, as: UInt64.self) }
        func u32(_ o: Int) -> UInt32 { base.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        if u64(IndexFormat.offMagic) != IndexFormat.magic { munmap(p, size); throw IndexError.badMagic }
        if u32(IndexFormat.offVersion) != IndexFormat.version { munmap(p, size); throw IndexError.badVersion }

        self.count = Int(u64(IndexFormat.offEntryCount))
        self.blobBytes = Int(u64(IndexFormat.offBlobBytes))

        func col<T>(_ offField: Int, _ : T.Type) -> UnsafePointer<T> {
            (base + Int(u64(offField))).assumingMemoryBound(to: T.self)
        }
        self.masks = col(IndexFormat.offMasksOff, UInt64.self)
        self.bnMasks = col(IndexFormat.offBnMasksOff, UInt64.self)
        self.bnBoundaries = col(IndexFormat.offBnBoundsOff, UInt64.self)
        self.pathOffset = col(IndexFormat.offPathOffOff, UInt32.self)
        self.pathLen = col(IndexFormat.offPathLenOff, UInt16.self)
        self.bnStart = col(IndexFormat.offBnStartOff, UInt16.self)
        self.extIDs = col(IndexFormat.offExtIDsOff, UInt16.self)
        self.flags = col(IndexFormat.offFlagsOff, UInt8.self)
        self.blob = col(IndexFormat.offBlobOff, UInt8.self)

        // Parse ext table into a dict for query-time resolution.
        var o = Int(u64(IndexFormat.offExtTableOff))
        let extCount = Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self)); o += 4
        for id in 0 ..< extCount {
            let len = Int((base + o).load(as: UInt8.self)); o += 1
            let s = String(decoding: UnsafeBufferPointer(start: (base + o).assumingMemoryBound(to: UInt8.self), count: len), as: UTF8.self)
            o += len
            extDict[s] = UInt16(id + 1)
        }
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), byteCount) }

    /// Reconstruct the (lowercased) path for entry `i`. Call only for visible results.
    public func path(_ i: Int) -> String {
        let off = Int(pathOffset[i]); let len = Int(pathLen[i])
        return String(decoding: UnsafeBufferPointer(start: blob + off, count: len), as: UTF8.self)
    }

    /// Pointer + length to the raw lowercased path bytes for entry `i` (for scoring).
    @inline(__always) public func pathBytes(_ i: Int) -> (UnsafePointer<UInt8>, Int) {
        (blob + Int(pathOffset[i]), Int(pathLen[i]))
    }

    public func extID(forExtension ext: String) -> UInt16 { extDict[ext.lowercased()] ?? 0 }

    /// Advise the kernel it can drop resident pages (called when app backgrounds).
    public func adviseDontNeed() { madvise(UnsafeMutableRawPointer(mutating: base), byteCount, MADV_DONTNEED) }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter IndexRoundTripTests/testReaderRoundTrip`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Index/IndexReader.swift Tests/ClingCoreTests/IndexRoundTripTests.swift
git commit -m "feat: mmap-in-place columnar index reader (no heap copy)"
```

---

## Task 9: Query parser

**Files:**
- Create: `Sources/ClingCore/Engine/QueryParser.swift`
- Test: `Tests/ClingCoreTests/QueryParserTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/QueryParserTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class QueryParserTests: XCTestCase {
    func testParsesTokenTypes() {
        let q = ParsedQuery(".png in:/Users/me icon depth:3 src/")
        XCTAssertEqual(q.extTokens, ["png"])
        XCTAssertEqual(q.folderPrefixes, ["/users/me"])
        XCTAssertEqual(q.dirSegments, ["src/"])
        XCTAssertEqual(q.depth, 3)
        XCTAssertEqual(q.fuzzyTokens, ["icon"])
    }

    func testCombinedMaskIsSupersetOfFuzzy() {
        let q = ParsedQuery("abc")
        let m = Array("abc".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        XCTAssertEqual(q.combinedMask & m, m)
    }

    func testEmptyQuery() {
        let q = ParsedQuery("   ")
        XCTAssertTrue(q.isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter QueryParserTests`
Expected: FAIL — `ParsedQuery` undefined.

- [ ] **Step 3: Implement `QueryParser.swift`**

```swift
import Foundation

/// Splits a raw query into typed tokens and precomputes letter masks. Mirrors Cling's parser
/// (SearchEngine.swift:1505-1577): `.ext`/`*.ext`, `in:<path>`, `depth:<n>`, `seg/`, fuzzy text.
public struct ParsedQuery {
    public let fuzzyTokens: [String]
    public let extTokens: [String]
    public let folderPrefixes: [String]
    public let dirSegments: [String]
    public let depth: Int?

    public let fuzzyBytes: [[UInt8]]     // lowercased, for scoring
    public let extTokenBytes: [[UInt8]]  // lowercased ext strings
    public let combinedMask: UInt64
    public let isEmpty: Bool

    public init(_ raw: String) {
        let lowered = raw.lowercased()
        let toks = lowered.split(separator: " ").map(String.init)

        func isExt(_ t: String) -> Bool { t.hasPrefix(".") || t.hasPrefix("*.") }
        func isIn(_ t: String) -> Bool { t.hasPrefix("in:") && t.count > 3 }
        func isDepth(_ t: String) -> Bool { t.hasPrefix("depth:") && t.count > 6 }
        func isDirSeg(_ t: String) -> Bool { t.hasSuffix("/") && t.count > 1 && !isIn(t) && !isDepth(t) }

        var fz = [String](), ext = [String](), folders = [String](), segs = [String]()
        var d: Int? = nil
        for t in toks {
            if isExt(t) { ext.append(t.hasPrefix("*.") ? String(t.dropFirst(2)) : String(t.dropFirst())) }
            else if isIn(t) { folders.append(String(t.dropFirst(3))) }
            else if isDepth(t) { d = Int(t.dropFirst(6)) }
            else if isDirSeg(t) { segs.append(t) }
            else { fz.append(t) }
        }

        self.fuzzyTokens = fz
        self.extTokens = ext
        self.folderPrefixes = folders
        self.dirSegments = segs
        self.depth = d
        self.fuzzyBytes = fz.map { Array($0.utf8) }
        self.extTokenBytes = ext.map { Array($0.utf8) }

        var m: UInt64 = 0
        for b in fuzzyBytes { m |= b.withUnsafeBufferPointer { letterMaskBytes($0) } }
        for b in extTokenBytes { m |= b.withUnsafeBufferPointer { letterMaskBytes($0) } }
        for s in segs { m |= Array(s.utf8).withUnsafeBufferPointer { letterMaskBytes($0) } }
        self.combinedMask = m

        self.isEmpty = fz.isEmpty && ext.isEmpty && folders.isEmpty && segs.isEmpty
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter QueryParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/QueryParser.swift Tests/ClingCoreTests/QueryParserTests.swift
git commit -m "feat: query parser (fuzzy/ext/folder/dir-seg/depth tokens + combined mask)"
```

---

## Task 10: Search engine (filter + score over the reader)

**Files:**
- Create: `Sources/ClingCore/Engine/SearchEngine.swift`
- Test: `Tests/ClingCoreTests/SearchTests.swift`

Two-phase search over the mmap reader: parallel mask-precheck filter (candidate pool capped at 50K), then parallel fzf scoring on candidate path bytes, then rank/dedup.

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/SearchTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class SearchTests: XCTestCase {
    private func buildReader(_ paths: [(String, Bool)]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("s-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0.0, isDir: $0.1) }, to: url)
        return try IndexReader(url: url)
    }

    func testFuzzyRanksBasenameMatchFirst() throws {
        let r = try buildReader([
            ("/Users/me/Documents/quarterly-report.pdf", false),
            ("/Users/me/repo/tools/rpt.sh", false),
            ("/Users/me/notes/groceries.txt", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search("rpt", maxResults: 10)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.path, "/users/me/repo/tools/rpt.sh")
    }

    func testExtensionFilter() throws {
        let r = try buildReader([
            ("/a/b/image.png", false),
            ("/a/b/doc.pdf", false),
            ("/a/b/photo.png", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search(".png", maxResults: 10)
        XCTAssertEqual(Set(hits.map { $0.path }), ["/a/b/image.png", "/a/b/photo.png"])
    }

    func testFolderPrefixFilter() throws {
        let r = try buildReader([
            ("/projects/alpha/main.swift", false),
            ("/projects/beta/main.swift", false),
        ])
        let eng = SearchEngine(reader: r)
        let hits = eng.search("main in:/projects/alpha", maxResults: 10)
        XCTAssertEqual(hits.map { $0.path }, ["/projects/alpha/main.swift"])
    }

    func testEmptyQueryReturnsNothing() throws {
        let r = try buildReader([("/a/b.txt", false)])
        XCTAssertTrue(SearchEngine(reader: r).search("", maxResults: 10).isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter SearchTests`
Expected: FAIL — `SearchEngine` undefined.

- [ ] **Step 3: Implement `SearchEngine.swift`**

```swift
import Foundation

public struct SearchHit: Comparable {
    public let id: Int
    public let path: String
    public let score: Int
    public let isDir: Bool
    public static func < (a: SearchHit, b: SearchHit) -> Bool { a.score > b.score } // higher first
    public static func == (a: SearchHit, b: SearchHit) -> Bool { a.score == b.score && a.path == b.path }
}

/// Two-phase search over a memory-mapped IndexReader.
public final class SearchEngine {
    private let r: IndexReader
    private let maxCandidates = 50_000
    public init(reader: IndexReader) { self.r = reader }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        let q = ParsedQuery(query)
        if q.isEmpty { return [] }
        let n = r.count
        if n == 0 { return [] }

        // Resolve extension tokens to IDs (0 = unknown -> nothing matches).
        let extIDset: Set<UInt16> = Set(q.extTokens.map { r.extID(forExtension: $0) })
        let filterByExt = !q.extTokens.isEmpty
        let folderBytes: [[UInt8]] = q.folderPrefixes.map { Array($0.utf8) }
        let combined = q.combinedMask
        let hasFuzzy = !q.fuzzyBytes.isEmpty

        // ---- Phase 1: parallel filter -> candidate ids ----
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk = (n + cores - 1) / cores
        let store = UnsafeMutablePointer<[Int]>.allocate(capacity: cores)
        store.initialize(repeating: [], count: cores)
        defer { store.deinitialize(count: cores); store.deallocate() }

        DispatchQueue.concurrentPerform(iterations: cores) { c in
            let lo = c * chunk, hi = min(lo + chunk, n)
            if lo >= hi { return }
            var local = [Int](); local.reserveCapacity((hi - lo) / 8)
            for i in lo ..< hi {
                if r.masks[i] & combined != combined { continue }
                if filterByExt, !extIDset.contains(r.extIDs[i]) { continue }
                if !folderBytes.isEmpty {
                    let (p, len) = r.pathBytes(i)
                    var ok = false
                    for pre in folderBytes where len >= pre.count {
                        var j = 0; var m = true
                        while j < pre.count { if p[j] != pre[j] { m = false; break }; j += 1 }
                        if m { ok = true; break }
                    }
                    if !ok { continue }
                }
                local.append(i)
                if local.count >= maxCandidates { break }
            }
            store[c] = local
        }
        var cands = [Int](); for c in 0 ..< cores { cands.append(contentsOf: store[c]) }
        if cands.count > maxCandidates { cands.removeLast(cands.count - maxCandidates) }

        // No fuzzy text (ext/folder-only): rank by shallow path, then alpha.
        if !hasFuzzy {
            var hits = cands.map { SearchHit(id: $0, path: r.path($0), score: 0, isDir: IndexFormat.isDir(r.flags[$0])) }
            hits.sort { $0.path.count < $1.path.count }
            return Array(hits.prefix(maxResults))
        }

        // ---- Phase 2: parallel score ----
        let nc = cands.count
        if nc == 0 { return [] }
        let scoreChunk = max(nc / cores, 512)
        let nChunks = (nc + scoreChunk - 1) / scoreChunk
        let scoreStore = UnsafeMutablePointer<[SearchHit]>.allocate(capacity: nChunks)
        scoreStore.initialize(repeating: [], count: nChunks)
        defer { scoreStore.deinitialize(count: nChunks); scoreStore.deallocate() }

        let tokens = q.fuzzyBytes
        DispatchQueue.concurrentPerform(iterations: nChunks) { ch in
            let lo = ch * scoreChunk, hi = min(lo + scoreChunk, nc)
            if lo >= hi { return }
            var local = [SearchHit](); local.reserveCapacity(hi - lo)
            for idx in lo ..< hi {
                let i = cands[idx]
                let (p, len) = r.pathBytes(i)
                let bnOff = Int(r.bnStart[i])
                let bnBits = r.bnBoundaries[i]
                var total = 0
                var allMatched = true
                for tok in tokens {
                    let matched: Int? = tok.withUnsafeBufferPointer { tb -> Int? in
                        let txt = UnsafeBufferPointer(start: p, count: len)
                        return fuzzyScoreBytes(tb, txt, boundaries: bnBits, boundariesOffset: bnOff)?.score
                    }
                    guard let s = matched else { allMatched = false; break }
                    total += s
                }
                if allMatched {
                    local.append(SearchHit(id: i, path: r.path(i), score: total, isDir: IndexFormat.isDir(r.flags[i])))
                }
            }
            scoreStore[ch] = local
        }

        var scored = [SearchHit](); for c in 0 ..< nChunks { scored.append(contentsOf: scoreStore[c]) }
        if scored.isEmpty { return [] }

        // Quality gate (top-third) + sort + dedup by path.
        let best = scored.max(by: { $0.score < $1.score })?.score ?? 0
        let minQ = best / 3
        scored = scored.filter { $0.score >= minQ }
        scored.sort()
        var seen = Set<String>(); var out = [SearchHit]()
        for h in scored where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter SearchTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/SearchEngine.swift Tests/ClingCoreTests/SearchTests.swift
git commit -m "feat: two-phase parallel search over mmap index (filter + fzf score)"
```

---

## Task 11: Minimal ignore matcher

**Files:**
- Create: `Sources/ClingCore/Indexer/IgnoreMatcher.swift`
- Test: `Tests/ClingCoreTests/IndexerTests.swift` (create; shared with Tasks 12-13)

Covers the common `.fsignore`/`.gitignore` patterns Cling ships by default: literal names, `*.ext`, and `dir/`.

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/IndexerTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class IndexerTests: XCTestCase {
    func testIgnoreMatcher() {
        let m = IgnoreMatcher(patterns: [".DS_Store", "*.log", "node_modules/", ".git/"])
        XCTAssertTrue(m.isIgnored(name: ".DS_Store", isDir: false))
        XCTAssertTrue(m.isIgnored(name: "debug.log", isDir: false))
        XCTAssertTrue(m.isIgnored(name: "node_modules", isDir: true))
        XCTAssertTrue(m.isIgnored(name: ".git", isDir: true))
        XCTAssertFalse(m.isIgnored(name: "main.swift", isDir: false))
        XCTAssertFalse(m.isIgnored(name: "node_modules", isDir: false)) // dir-only pattern
    }

    func testComments与Blank() {
        let m = IgnoreMatcher(text: "# comment\n\n*.tmp\n")
        XCTAssertTrue(m.isIgnored(name: "a.tmp", isDir: false))
    }
}
```

> Note: rename the second test method to `testCommentsAndBlank` (ASCII only) when implementing — the placeholder above contains a non-ASCII char intentionally so you fix it; Swift identifiers should be ASCII here.

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexerTests/testIgnoreMatcher`
Expected: FAIL — `IgnoreMatcher` undefined.

- [ ] **Step 3: Implement `IgnoreMatcher.swift`**

```swift
import Foundation

/// Minimal gitignore-style matcher: literal names, `*.ext` suffix globs, and `dir/` (dir-only).
/// Matches against a single path component (the entry's basename) at walk time.
public struct IgnoreMatcher {
    private var literals = Set<String>()
    private var dirLiterals = Set<String>()
    private var suffixes = [String]() // from "*.ext" -> ".ext"

    public init(patterns: [String]) {
        for raw in patterns {
            let p = raw.trimmingCharacters(in: .whitespaces)
            if p.isEmpty || p.hasPrefix("#") { continue }
            if p.hasSuffix("/") { dirLiterals.insert(String(p.dropLast())); continue }
            if p.hasPrefix("*.") { suffixes.append(String(p.dropFirst())); continue }
            literals.insert(p)
        }
    }

    public init(text: String) { self.init(patterns: text.split(separator: "\n").map(String.init)) }

    public func isIgnored(name: String, isDir: Bool) -> Bool {
        if literals.contains(name) { return true }
        if isDir, dirLiterals.contains(name) { return true }
        for s in suffixes where name.hasSuffix(s) { return true }
        return false
    }

    public var isEmpty: Bool { literals.isEmpty && dirLiterals.isEmpty && suffixes.isEmpty }
}
```

- [ ] **Step 4: Fix the test identifier and run, verify pass**

Edit `IndexerTests`: rename `testComments与Blank` → `testCommentsAndBlank`. Then:
Run: `swift test --filter IndexerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Indexer/IgnoreMatcher.swift Tests/ClingCoreTests/IndexerTests.swift
git commit -m "feat: minimal gitignore-style ignore matcher"
```

---

## Task 12: Filesystem walker (`fts_read`)

**Files:**
- Create: `Sources/ClingCore/Indexer/FileWalker.swift`
- Test: append to `Tests/ClingCoreTests/IndexerTests.swift`

Uses Darwin's `fts(3)` for a fast C-level recursive walk, applying the ignore matcher per component.

- [ ] **Step 1: Add the failing test** to `IndexerTests`:

```swift
    func testWalkerEnumeratesTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("walk-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "y".write(to: root.appendingPathComponent("sub/b.swift"), atomically: true, encoding: .utf8)
        try "z".write(to: root.appendingPathComponent("ignore.log"), atomically: true, encoding: .utf8)

        var found = [String]()
        let walker = FileWalker(ignore: IgnoreMatcher(patterns: ["*.log"]))
        walker.walk(root: root.path) { entry in found.append(entry.path) }

        XCTAssertTrue(found.contains { $0.hasSuffix("/a.txt") })
        XCTAssertTrue(found.contains { $0.hasSuffix("/sub/b.swift") })
        XCTAssertFalse(found.contains { $0.hasSuffix("ignore.log") })
        try? fm.removeItem(at: root)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexerTests/testWalkerEnumeratesTree`
Expected: FAIL — `FileWalker` undefined.

- [ ] **Step 3: Implement `FileWalker.swift`**

```swift
import Foundation

/// Fast recursive filesystem walk via fts(3). Emits a RawEntry per file and directory,
/// skipping entries (and pruning directories) that the ignore matcher rejects.
public final class FileWalker {
    private let ignore: IgnoreMatcher
    public init(ignore: IgnoreMatcher) { self.ignore = ignore }

    public func walk(root: String, _ emit: (RawEntry) -> Void) {
        root.withCString { c0 in
            let paths: [UnsafeMutablePointer<CChar>?] = [strdup(c0), nil]
            let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: paths.count)
            argv.initialize(from: paths, count: paths.count)
            defer { free(paths[0]); argv.deallocate() }

            guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
            defer { fts_close(fts) }

            while let ent = fts_read(fts) {
                let info = Int32(ent.pointee.fts_info)
                let isDir = info == FTS_D
                // FTS_D = pre-order dir, FTS_F = file, FTS_DP = post-order dir (skip dup), others skip.
                if info == FTS_DP { continue }
                if info != FTS_D && info != FTS_F { continue }

                let namePtr = ent.pointee.fts_name
                let name = withUnsafePointer(to: namePtr) { p in
                    String(cString: UnsafeRawPointer(p).assumingMemoryBound(to: CChar.self))
                }
                // Skip the root entry's own emission filter, but always apply ignore to children.
                let depth = ent.pointee.fts_level
                if depth > 0, ignore.isIgnored(name: name, isDir: isDir) {
                    if isDir { fts_set(fts, ent, FTS_SKIP) } // prune subtree
                    continue
                }
                let path = String(cString: ent.pointee.fts_path)
                if depth > 0 { emit(RawEntry(path: path, isDir: isDir)) }
            }
        }
    }
}
```

> Implementation note: `fts_name` is a C fixed-size tuple member; if the `withUnsafePointer` decoding misbehaves on this SDK, fall back to deriving the component from `String(cString: ent.pointee.fts_path)` via `(path as NSString).lastPathComponent`. Keep the `fts_path`-based name if so; the test only checks final paths.

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter IndexerTests/testWalkerEnumeratesTree`
Expected: PASS. (If it fails on name decoding, apply the fallback in the note, then re-run.)

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Indexer/FileWalker.swift Tests/ClingCoreTests/IndexerTests.swift
git commit -m "feat: fts(3) filesystem walker with ignore pruning"
```

---

## Task 13: Indexer orchestration

**Files:**
- Create: `Sources/ClingCore/Indexer/Indexer.swift`
- Test: append to `Tests/ClingCoreTests/IndexerTests.swift`

- [ ] **Step 1: Add the failing test** to `IndexerTests`:

```swift
    func testIndexerEndToEnd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("idx-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let idx = root.appendingPathComponent("out.idx")
        let count = try Indexer.build(root: root.path, ignore: IgnoreMatcher(patterns: []), output: idx)
        XCTAssertGreaterThanOrEqual(count, 3) // src, Engine.swift, README.md

        let r = try IndexReader(url: idx)
        let hits = SearchEngine(reader: r).search("engine", maxResults: 10)
        XCTAssertTrue(hits.contains { $0.path.hasSuffix("/src/engine.swift") })
        try? fm.removeItem(at: root)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter IndexerTests/testIndexerEndToEnd`
Expected: FAIL — `Indexer` undefined.

- [ ] **Step 3: Implement `Indexer.swift`**

```swift
import Foundation

/// Walks `root`, collects RawEntry values, and writes a .idx via IndexWriter. Returns entry count.
public enum Indexer {
    public static func build(root: String, ignore: IgnoreMatcher, output: URL) throws -> Int {
        var entries = [RawEntry]()
        entries.reserveCapacity(1 << 16)
        FileWalker(ignore: ignore).walk(root: root) { entries.append($0) }
        try IndexWriter.write(entries: entries, to: output)
        return entries.count
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter IndexerTests/testIndexerEndToEnd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Indexer/Indexer.swift Tests/ClingCoreTests/IndexerTests.swift
git commit -m "feat: indexer orchestration (walk -> write .idx)"
```

---

## Task 14: Base + delta live updates

**Files:**
- Create: `Sources/ClingCore/Engine/Delta.swift`
- Test: `Tests/ClingCoreTests/DeltaTests.swift`

The immutable mmap base never changes at runtime. New/changed files go into a small in-heap delta; deletes/moves record a tombstone keyed by path. Search merges base (minus tombstones) with the delta.

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/DeltaTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class DeltaTests: XCTestCase {
    private func reader(_ paths: [String]) throws -> IndexReader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("d-\(UUID().uuidString).idx")
        try IndexWriter.write(entries: paths.map { RawEntry(path: $0, isDir: false) }, to: url)
        return try IndexReader(url: url)
    }

    func testAddedFileAppearsAndDeletedDisappears() throws {
        let r = try reader(["/a/old.swift", "/a/keep.swift"])
        let live = LiveIndex(base: r)
        live.add(RawEntry(path: "/a/brandnew.swift", isDir: false))
        live.remove(path: "/a/old.swift")

        let hits = live.search("swift", maxResults: 10).map { $0.path }
        XCTAssertTrue(hits.contains("/a/brandnew.swift"))   // delta add visible
        XCTAssertTrue(hits.contains { $0.hasSuffix("keep.swift") })
        XCTAssertFalse(hits.contains("/a/old.swift"))       // tombstoned base entry hidden
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter DeltaTests`
Expected: FAIL — `LiveIndex` undefined.

- [ ] **Step 3: Implement `Delta.swift`**

```swift
import Foundation

/// Combines an immutable mmap base with an in-heap delta (recent adds) and a tombstone set
/// (deleted/moved base paths). Search results from both are merged, deduped, and re-ranked.
public final class LiveIndex {
    private let base: IndexReader
    private let baseEngine: SearchEngine
    private var deltaEntries = [RawEntry]()
    private var tombstones = Set<String>() // lowercased paths hidden from base
    private let lock = NSLock()

    public init(base: IndexReader) {
        self.base = base
        self.baseEngine = SearchEngine(reader: base)
    }

    public func add(_ e: RawEntry) {
        lock.lock(); defer { lock.unlock() }
        tombstones.remove(e.path.lowercased()) // re-added path is no longer dead
        deltaEntries.append(e)
    }

    public func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        let lc = path.lowercased()
        tombstones.insert(lc)
        deltaEntries.removeAll { $0.path.lowercased() == lc }
    }

    public func search(_ query: String, maxResults: Int) -> [SearchHit] {
        lock.lock()
        let tomb = tombstones
        let delta = deltaEntries
        lock.unlock()

        // Base hits minus tombstones.
        var hits = baseEngine.search(query, maxResults: maxResults * 2).filter { !tomb.contains($0.path) }

        // Delta hits: build a throwaway in-memory reader over just the delta and search it.
        if !delta.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("delta-\(UUID().uuidString).idx")
            defer { try? FileManager.default.removeItem(at: url) }
            if (try? IndexWriter.write(entries: delta, to: url)) != nil,
               let dr = try? IndexReader(url: url) {
                hits.append(contentsOf: SearchEngine(reader: dr).search(query, maxResults: maxResults * 2))
            }
        }

        hits.sort()
        var seen = Set<String>(); var out = [SearchHit]()
        for h in hits where seen.insert(h.path).inserted {
            out.append(h); if out.count >= maxResults { break }
        }
        return out
    }
}
```

> Performance note for Plan B: rebuilding a delta `.idx` per search is fine while the delta is small (recent churn). Phase B will add a threshold that triggers a full background re-index (folding delta into a fresh base) when the delta grows past a few thousand entries, keeping per-search cost flat.

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter DeltaTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/Delta.swift Tests/ClingCoreTests/DeltaTests.swift
git commit -m "feat: base+delta+tombstone live index for FSEvents updates"
```

---

## Task 15: Memory helpers + background eviction

**Files:**
- Create: `Sources/ClingCore/Engine/Memory.swift`
- Test: append to `Tests/ClingCoreTests/MemoryHarnessTests.swift` (create; shared with Task 16)

- [ ] **Step 1: Write the failing test**

`Tests/ClingCoreTests/MemoryHarnessTests.swift`:

```swift
import XCTest
@testable import ClingCore

final class MemoryHarnessTests: XCTestCase {
    func testResidentBytesIsPositive() {
        XCTAssertGreaterThan(currentResidentBytes(), 0)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter MemoryHarnessTests/testResidentBytesIsPositive`
Expected: FAIL — `currentResidentBytes` undefined.

- [ ] **Step 3: Implement `Memory.swift`**

```swift
import Foundation
import Darwin

/// Current process resident memory in bytes (phys_footprint), via task_info.
public func currentResidentBytes() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter MemoryHarnessTests/testResidentBytesIsPositive`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClingCore/Engine/Memory.swift Tests/ClingCoreTests/MemoryHarnessTests.swift
git commit -m "feat: resident-memory probe (phys_footprint via task_info)"
```

---

## Task 16: Memory-ceiling proof harness (THE GATE)

**Files:**
- Modify: `Tests/ClingCoreTests/MemoryHarnessTests.swift`

This is the test that **proves the <500MB goal**. It synthesizes a large index, opens it via the mmap reader, runs representative searches, and asserts the resident footprint stays under a ceiling and searches stay fast.

- [ ] **Step 1: Add the failing harness test** to `MemoryHarnessTests`:

```swift
    /// Build a synthetic index of `n` plausible file paths without touching the real FS.
    private func buildSyntheticIndex(_ n: Int) throws -> URL {
        let dirs = ["Users/me/Documents", "Users/me/Code/project/src", "Library/Caches/app",
                    "Users/me/Pictures/2026", "Applications/Tool.app/Contents/Resources"]
        let exts = ["swift", "png", "pdf", "txt", "json", "md", "log", "mp4"]
        var entries = [RawEntry](); entries.reserveCapacity(n)
        for i in 0 ..< n {
            let d = dirs[i % dirs.count]
            let e = exts[i % exts.count]
            entries.append(RawEntry(path: "/\(d)/file_\(i)_report_data.\(e)", isDir: false))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(n).idx")
        try? FileManager.default.removeItem(at: url)
        try IndexWriter.write(entries: entries, to: url)
        return url
    }

    func testMemoryCeilingAndLatencyAt2MFiles() throws {
        // 2,000,000 files ~ matches the user's current ~1GB filesystem scale.
        let n = 2_000_000
        let url = try buildSyntheticIndex(n)
        defer { try? FileManager.default.removeItem(at: url) }

        let before = currentResidentBytes()
        let reader = try IndexReader(url: url)
        let engine = SearchEngine(reader: reader)
        XCTAssertEqual(reader.count, n)

        // Run several representative searches (forces candidate pages to fault in).
        let queries = ["report", "file data", ".png", "src/ swift", "report in:/Users/me/Documents"]
        var totalMs = 0.0
        for q in queries {
            let t0 = Date()
            let hits = engine.search(q, maxResults: 200)
            totalMs += Date().timeIntervalSince(t0) * 1000
            XCTAssertLessThanOrEqual(hits.count, 200)
        }

        let after = currentResidentBytes()
        let usedMB = Double(after - before) / 1_048_576.0
        let avgMs = totalMs / Double(queries.count)
        print("[harness] n=\(n) idxSize=\(reader.byteCount / 1_048_576)MB residentDelta=\(Int(usedMB))MB avgSearch=\(String(format: "%.1f", avgMs))ms")

        // HARD CEILING: the search working set for 2M files must stay well under 500MB.
        XCTAssertLessThan(usedMB, 400.0, "resident working set exceeded ceiling")
        // SPEED: representative searches must remain interactive.
        XCTAssertLessThan(avgMs, 150.0, "search latency regressed (note: debug build; release is faster)")
    }
```

- [ ] **Step 2: Run in RELEASE (representative of shipping perf)**

Run: `swift test -c release --filter MemoryHarnessTests/testMemoryCeilingAndLatencyAt2MFiles`
Expected: PASS. Inspect the `[harness]` line — `residentDelta` should be roughly the masks/extIDs hot set plus faulted candidate pages (target well under 400MB), `avgSearch` well under 100ms in release.

> If the resident delta is higher than expected, the likely cause is the writer's `Data`-based assembly holding the whole file during `build` — that is the *writer's* transient cost, not the *reader's*. The harness measures around the reader open + searches, after the writer returns and its buffers are freed, so it isolates the runtime ceiling. If `IndexWriter.write` itself OOMs at 2M during the build, switch the writer to stream sections to a `FileHandle` (documented as a Plan B optimization) and keep this harness at 2M.

- [ ] **Step 3: Commit**

```bash
git add Tests/ClingCoreTests/MemoryHarnessTests.swift
git commit -m "test: memory-ceiling + latency proof harness at 2M files"
```

---

## Task 17: `cling` CLI (hand-rolled args)

**Files:**
- Modify: `Sources/cling/main.swift`
- Test: `Tests/ClingCoreTests/CLITests.swift`

Subcommands: `cling index <root> <out.idx> [--ignore <file>]` and `cling search <out.idx> <query...>`.

- [ ] **Step 1: Write the failing CLI integration test**

`Tests/ClingCoreTests/CLITests.swift`:

```swift
import XCTest

final class CLITests: XCTestCase {
    /// Locate the built `cling` binary next to the test bundle.
    private func clingBinary() -> URL {
        Bundle(for: CLITests.self).bundleURL          // .../ClingLitePackageTests.xctest
            .deletingLastPathComponent()              // .../debug
            .appendingPathComponent("cling")
    }

    private func run(_ args: [String]) throws -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = clingBinary()
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    func testIndexThenSearch() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        let idx = root.appendingPathComponent("out.idx")

        let r1 = try run(["index", root.path, idx.path])
        XCTAssertEqual(r1.code, 0, r1.out)

        let r2 = try run(["search", idx.path, "engine"])
        XCTAssertEqual(r2.code, 0, r2.out)
        XCTAssertTrue(r2.out.lowercased().contains("engine.swift"), r2.out)
        try? fm.removeItem(at: root)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter CLITests`
Expected: FAIL — CLI prints version only / no `engine.swift` in output.

- [ ] **Step 3: Implement `Sources/cling/main.swift`**

```swift
import ClingCore
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage:
      cling index <root> <out.idx> [--ignore <patternsFile>]
      cling search <out.idx> <query...>
    """.utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "index":
    guard args.count >= 3 else { usage() }
    let root = args[1]
    let out = URL(fileURLWithPath: args[2])
    var patterns = [String]()
    if let i = args.firstIndex(of: "--ignore"), i + 1 < args.count,
       let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) {
        patterns = text.split(separator: "\n").map(String.init)
    }
    do {
        let n = try Indexer.build(root: root, ignore: IgnoreMatcher(patterns: patterns), output: out)
        print("indexed \(n) entries -> \(out.path)")
    } catch { FileHandle.standardError.write(Data("index failed: \(error)\n".utf8)); exit(1) }

case "search":
    guard args.count >= 3 else { usage() }
    let idx = URL(fileURLWithPath: args[1])
    let query = args[2...].joined(separator: " ")
    do {
        let reader = try IndexReader(url: idx)
        let hits = SearchEngine(reader: reader).search(query, maxResults: 200)
        for h in hits { print(h.path) }
    } catch { FileHandle.standardError.write(Data("search failed: \(error)\n".utf8)); exit(1) }

case "--version", "-v":
    print("cling \(ClingCore.version)")

default:
    usage()
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift build && swift test --filter CLITests`
Expected: PASS — output contains `engine.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/cling/main.swift Tests/ClingCoreTests/CLITests.swift
git commit -m "feat: cling CLI (index + search subcommands)"
```

---

## Task 18: Full suite green + release build smoke

**Files:** none (verification task)

- [ ] **Step 1: Run the full test suite (debug)**

Run: `cd ~/Documents/clinglite && swift test 2>&1 | tail -25`
Expected: all tests pass, 0 failures.

- [ ] **Step 2: Run the full suite (release, includes the memory harness)**

Run: `swift test -c release 2>&1 | tail -30`
Expected: all pass; inspect the `[harness]` line and confirm residentDelta < 400MB and avgSearch < 100ms.

- [ ] **Step 3: Real-filesystem smoke via CLI**

Run:
```bash
cd ~/Documents/clinglite && swift build -c release
.build/release/cling index "$HOME/Documents" /tmp/home-docs.idx
.build/release/cling search /tmp/home-docs.idx report
ls -lh /tmp/home-docs.idx
```
Expected: index builds, search returns plausible matches, `.idx` size is reasonable (tens of MB for Documents).

- [ ] **Step 4: Commit a short STATUS note**

```bash
cd ~/Documents/clinglite
printf '%s\n' "# ClingLite — Plan A complete" "Engine core, mmap SoA index, indexer, live delta, CLI, and memory-ceiling harness all green." > STATUS.md
git add STATUS.md
git commit -m "docs: Plan A (engine core) complete and verified"
```

---

## Self-Review

**Spec coverage (spec §3–§9):**
- §3 mmap-in-place SoA, no String column, hot `masks`-only scan, evictable pages → Tasks 6–8, 10, 15–16.
- §3.5 lazy per-scope loading → reader is per-file; multi-scope orchestration is Plan B (each scope = one IndexReader, opened on demand). Noted.
- §3.6 base+delta+tombstone → Task 14.
- §4 search pipeline (parse, parallel filter, parallel fzf score, rank/dedup, 50K cap) → Tasks 5, 9, 10.
- §4 indexer (`fts_read` + ignore) → Tasks 11–13.
- §7 build (SwiftPM/CLT) → Task 1 (`.app` bundling is Plan B).
- §8 verification (scorer parity, RSS harness, latency) → Tasks 2–5, 16, 18.
- Deferred to Plan B (GUI): window/hotkey/results/actions/preview/settings/onboarding/.app bundle, multi-scope orchestration UI, syntax highlighting. Explicitly out of Plan A scope.

**Placeholder scan:** No TBD/TODO. One intentional non-ASCII test identifier in Task 11 with an explicit fix step (teaches the fix; resolved before commit). Task 12 carries a documented `fts_name` fallback (a real API risk, not a placeholder). Both have concrete resolution steps.

**Type consistency:** `RawEntry(path:isDir:)`, `IndexWriter.write(entries:to:)`, `IndexReader(url:)` + columns (`masks`/`bnMasks`/`bnBoundaries`/`pathOffset`/`pathLen`/`bnStart`/`extIDs`/`flags`/`blob`) + `path(_:)`/`pathBytes(_:)`/`extID(forExtension:)`/`adviseDontNeed()`, `ParsedQuery(_:)` fields, `SearchEngine(reader:)`+`search(_:maxResults:)`→`[SearchHit]`, `LiveIndex(base:)`+`add`/`remove`/`search`, `currentResidentBytes()`, `Indexer.build(root:ignore:output:)`, `FileWalker(ignore:)`+`walk(root:_:)`, `IgnoreMatcher(patterns:)`/`(text:)`+`isIgnored(name:isDir:)`, `IndexFormat` constants/helpers — all consistent across tasks.

**Risk callouts:** (1) `fts_name` decoding — fallback documented in Task 12. (2) Writer transient memory at 2M during build — isolated by the harness and flagged for a streaming-writer optimization in Plan B. (3) Debug-build latency — harness runs in release; thresholds account for it.
