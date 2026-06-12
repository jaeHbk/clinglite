import Testing
import Foundation
@testable import ClingCore

@Suite struct IndexRoundTripTests {
    @Test func headerConstants() {
        #expect(IndexFormat.headerSize == 128)
        #expect(IndexFormat.magic == 0x434C_4E47_4C49_5431) // "CLNGLIT1"
        #expect(IndexFormat.version == 1)
    }

    @Test func flagPacking() {
        let f = IndexFormat.packFlags(isDir: true, segCount: 5)
        #expect(IndexFormat.isDir(f))
        #expect(IndexFormat.segCount(f) == 5)
        let g = IndexFormat.packFlags(isDir: false, segCount: 200) // clamps to 127
        #expect(!IndexFormat.isDir(g))
        #expect(IndexFormat.segCount(g) == 127)
    }
}
