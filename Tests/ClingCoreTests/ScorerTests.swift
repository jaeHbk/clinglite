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
}
