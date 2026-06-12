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
