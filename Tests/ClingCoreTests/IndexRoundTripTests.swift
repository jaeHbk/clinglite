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

    @Test func writerProducesValidHeader() throws {
        let entries = [
            RawEntry(path: "/Users/me/Documents/report.pdf", isDir: false),
            RawEntry(path: "/Users/me/Pictures", isDir: true),
            RawEntry(path: "/Users/me/Code/main.swift", isDir: false),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t1.idx")
        try? FileManager.default.removeItem(at: url)
        try IndexWriter.write(entries: entries, to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > IndexFormat.headerSize)
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self) }
        #expect(magic == IndexFormat.magic)
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) }
        #expect(count == 3)
        try? FileManager.default.removeItem(at: url)
    }
}
