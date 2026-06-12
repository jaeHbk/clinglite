import Foundation

@inline(__always) func toLowerByte(_ b: UInt8) -> UInt8 { (b >= 0x41 && b <= 0x5A) ? b &+ 32 : b }

/// fzf-style alignment scorer over raw bytes. Returns best (score, start, end) or nil if no match.
/// `boundaries`/`boundariesOffset` carry precomputed camelCase/delimiter boundary bits for the
/// text region so bonuses survive lowercasing.
func fuzzyScoreBytes(
    _ pat: UnsafeBufferPointer<UInt8>,
    _ txt: UnsafeBufferPointer<UInt8>,
    boundaries: UInt64 = 0,
    boundariesOffset: Int = 0
) -> (score: Int, start: Int, end: Int)? {
    let M = pat.count, N = txt.count
    if M == 0 { return (0, 0, 0) }
    if M > N { return nil }

    let txtBase = txt.baseAddress!
    let firstChar = pat[0]

    var bestScore = Int.min
    var bestStart = -1
    var bestEnd = -1

    var anchorFrom = 0
    var anchorsTried = 0
    let maxAnchors = 32

    while anchorsTried < maxAnchors {
        let anchor = simdFindByte(txtBase, count: N, needle: firstChar, from: anchorFrom)
        if anchor < 0 { break }
        if anchor &+ M > N { break }

        var pi = 1
        var searchFrom = anchor &+ 1
        var lastPos = anchor
        var matched = true
        while pi < M {
            let pos = simdFindByte(txtBase, count: N, needle: pat[pi], from: searchFrom)
            if pos < 0 { matched = false; break }
            lastPos = pos
            searchFrom = pos &+ 1
            pi &+= 1
        }
        if !matched { break }

        let eidx = lastPos &+ 1
        var sidx = anchor

        pi = M &- 1
        var bi = eidx &- 1
        while bi >= anchor {
            if txtBase[bi] == pat[pi] {
                pi &-= 1
                if pi < 0 { sidx = bi; break }
            }
            bi &-= 1
        }

        var score = 0, consecutive = 0, firstBonus = 0, inGap = false
        var prevCC = sidx > 0 ? ccTable[Int(txt[sidx &- 1])].rawValue : CC.delim.rawValue
        pi = 0
        for i in sidx ..< eidx {
            let b = txt[i]
            let curCC = ccTable[Int(b)].rawValue
            if toLowerByte(b) == pat[pi] {
                score &+= scoreMatch
                var bonus = bonusFlat[prevCC &* ccCount &+ curCC]
                if boundaries != 0 {
                    let bpos = i &- boundariesOffset
                    if bpos >= 0, bpos < 64, boundaries & (1 << UInt64(bpos)) != 0 {
                        bonus = max(bonus, bonusBoundary)
                    }
                }
                if consecutive == 0 {
                    firstBonus = bonus
                } else {
                    if bonus >= bonusBoundary, bonus > firstBonus { firstBonus = bonus }
                    bonus = max(bonus, max(bonusConsec, firstBonus))
                }
                score &+= pi == 0 ? bonus &* firstCharMul : bonus
                inGap = false; consecutive &+= 1; pi &+= 1
            } else {
                score &+= inGap ? gapExtend : gapStart
                inGap = true; consecutive = 0; firstBonus = 0
            }
            prevCC = curCC
        }

        if score > bestScore {
            bestScore = score
            bestStart = sidx
            bestEnd = eidx
        }

        anchorFrom = anchor &+ 1
        anchorsTried &+= 1
    }

    return bestStart < 0 ? nil : (bestScore, bestStart, bestEnd)
}
