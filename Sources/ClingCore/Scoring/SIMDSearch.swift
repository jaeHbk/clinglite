import simd

/// First occurrence of `needle` at or after `from`, scanning 16 bytes at a time. -1 if absent.
@inline(__always)
func simdFindByte(_ base: UnsafePointer<UInt8>, count: Int, needle: UInt8, from: Int) -> Int {
    let needleVec = SIMD16<UInt8>(repeating: needle)
    var i = from
    while i &+ 16 <= count {
        let block = UnsafeRawPointer(base + i).loadUnaligned(as: SIMD16<UInt8>.self)
        let cmp = block .== needleVec
        var lane = 0
        while lane < 16 {
            if cmp[lane] { return i &+ lane }
            lane &+= 1
        }
        i &+= 16
    }
    while i < count {
        if base[i] == needle { return i }
        i &+= 1
    }
    return -1
}
