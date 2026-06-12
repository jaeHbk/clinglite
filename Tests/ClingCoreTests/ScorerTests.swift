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
}
