import Testing
@testable import ClingCore

@Suite struct MaskTests {
    @Test func charClassTable() {
        #expect(ccTable[Int(UInt8(ascii: "a"))] == .lower)
        #expect(ccTable[Int(UInt8(ascii: "Z"))] == .upper)
        #expect(ccTable[Int(UInt8(ascii: "5"))] == .number)
        #expect(ccTable[Int(UInt8(ascii: "/"))] == .delim)
        #expect(ccTable[Int(UInt8(ascii: " "))] == .white)
    }

    @Test func bonusFlatCamel() {
        #expect(bonusFlat[CC.lower.rawValue * ccCount + CC.upper.rawValue] > 0)
    }

    @Test func letterMask() {
        let bytes = Array("ab.".utf8)
        let m = bytes.withUnsafeBufferPointer { letterMaskBytes($0) }
        // bit0 = 'a', bit1 = 'b', bit36 = '.'
        #expect(m == (1 << 0) | (1 << 1) | (1 << 36))
    }

    @Test func maskSupersetProperty() {
        let q = Array("abc".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        let t = Array("xabcz".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        #expect(t & q == q)
    }
}
