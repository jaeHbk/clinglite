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
}
