import Foundation

/// 64-bit presence bitmask: a-z -> bits 0..25, 0-9 -> bits 26..35, '.' 36, '-' 37, '_' 38.
@inline(__always)
func letterMaskBytes(_ p: UnsafeBufferPointer<UInt8>) -> UInt64 {
    var m: UInt64 = 0
    for i in 0 ..< p.count {
        let v = p[i]
        if v >= 0x61, v <= 0x7A { m |= 1 << UInt64(v &- 0x61) }
        else if v >= 0x30, v <= 0x39 { m |= 1 << UInt64(26 &+ v &- 0x30) }
        else if v == 0x2E { m |= 1 << 36 }
        else if v == 0x2D { m |= 1 << 37 }
        else if v == 0x5F { m |= 1 << 38 }
    }
    return m
}
