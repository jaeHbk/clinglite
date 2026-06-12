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
