import Foundation

// Scoring constants (ported from Cling SearchEngine.swift; tuned fzf-style weights).
let scoreMatch = 16
let gapStart = -3
let gapExtend = -1
let bonusBoundary = 8
let bonusConsec = 4
let firstCharMul = 2

// Boundary bonus variants used by bonusFlat.
let bonusBdWhite = 10
let bonusBdDelim = 9
let bonusCamel123 = 7
let bonusNonWord = 6

enum CC: Int { case white = 0, nonWord, delim, lower, upper, letter, number }
let ccCount = 7

let ccTable: [CC] = {
    var t = [CC](repeating: .nonWord, count: 256)
    for i in 0x61 ... 0x7A { t[i] = .lower }   // a-z
    for i in 0x41 ... 0x5A { t[i] = .upper }   // A-Z
    for i in 0x30 ... 0x39 { t[i] = .number }  // 0-9
    for v: Int in [0x09, 0x0A, 0x0D, 0x20] { t[v] = .white }
    for v: Int in [0x2F, 0x2D, 0x5F, 0x2E, 0x2C, 0x3A, 0x3B, 0x7C] { t[v] = .delim }
    return t
}()

private func buildBonusFlat() -> [Int] {
    func b(_ p: CC, _ c: CC) -> Int {
        if c.rawValue > CC.nonWord.rawValue {
            switch p {
            case .white: return bonusBdWhite
            case .delim: return bonusBdDelim
            case .nonWord: return bonusBoundary
            default: break
            }
        }
        if p == .lower, c == .upper { return bonusCamel123 }
        if p != .number, c == .number { return bonusCamel123 }
        switch c {
        case .nonWord, .delim: return bonusNonWord
        case .white: return bonusBdWhite
        default: return 0
        }
    }
    var m = [Int](repeating: 0, count: ccCount * ccCount)
    for p in 0 ..< ccCount {
        for c in 0 ..< ccCount {
            m[p * ccCount + c] = b(CC(rawValue: p)!, CC(rawValue: c)!)
        }
    }
    return m
}

let bonusFlat: [Int] = buildBonusFlat()
