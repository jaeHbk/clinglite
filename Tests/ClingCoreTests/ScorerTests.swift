import Testing
@testable import ClingCore

@Suite struct ScorerTests {
    @Test func simdFind() {
        let s = Array("the quick brown fox jumps over the lazy dog".utf8)
        s.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            #expect(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "q"), from: 0) == 4)
            #expect(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "z"), from: 0) == 37)
            #expect(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "X"), from: 0) == -1)
            #expect(simdFindByte(base, count: buf.count, needle: UInt8(ascii: "t"), from: 1) == 31)
        }
    }

    private func score(_ pat: String, _ txt: String) -> Int? {
        let p = Array(pat.utf8), t = Array(txt.utf8)
        return p.withUnsafeBufferPointer { pb in
            t.withUnsafeBufferPointer { tb in
                fuzzyScoreBytes(pb, tb)?.score
            }
        }
    }

    @Test func emptyPatternScoresZero() {
        #expect(score("", "anything") == 0)
    }

    @Test func noMatchReturnsNil() {
        #expect(score("xyz", "abc") == nil)
    }

    @Test func anchorEnumerationPrefersTighterSegment() {
        let tight = score("lnr", "lunar")!
        let scattered = score("lnr", "alintnr")!
        #expect(tight > scattered)
    }

    @Test func consecutiveBeatsGapped() {
        #expect(score("abc", "abc")! > score("abc", "axbxc")!)
    }

    @Test func boundaryBitsRaiseScore() {
        // Same lowercased text and pattern; the only difference is whether we tell the scorer
        // that the matched 'w'/'r' positions are word boundaries. The boundary bonus must
        // raise the score for those matched characters.
        let txt = Array("midweekreport".utf8)
        let pat = Array("mwr".utf8)  // matches at m(0) w(3) r(7) in "midweekreport"
        let withoutBits: Int = pat.withUnsafeBufferPointer { pb in
            txt.withUnsafeBufferPointer { tb in fuzzyScoreBytes(pb, tb, boundaries: 0, boundariesOffset: 0)!.score }
        }
        // Mark the matched positions 3 ('w') and 7 ('r') as boundaries.
        let bits: UInt64 = (1 << 3) | (1 << 7)
        let withBits: Int = pat.withUnsafeBufferPointer { pb in
            txt.withUnsafeBufferPointer { tb in fuzzyScoreBytes(pb, tb, boundaries: bits, boundariesOffset: 0)!.score }
        }
        #expect(withBits > withoutBits)
    }
}
