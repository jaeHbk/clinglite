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
        let base = UnsafeRawPointer(p)
        self.base = base
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
        var dict = [String: UInt16]()
        for id in 0 ..< extCount {
            let len = Int((base + o).load(as: UInt8.self)); o += 1
            let s = String(decoding: UnsafeBufferPointer(start: (base + o).assumingMemoryBound(to: UInt8.self), count: len), as: UTF8.self)
            o += len
            dict[s] = UInt16(id + 1)
        }
        self.extDict = dict
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
