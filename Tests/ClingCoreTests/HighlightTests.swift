import Testing
@testable import ClingCore

@Suite struct HighlightTests {
    @Test func contiguousMatchIsOneRange() {
        // "eng" matches the leading "eng" of "engine.swift" -> a single 0..<3 range.
        let ranges = fuzzyHighlightRanges(query: "eng", in: "engine.swift")
        #expect(ranges == [0 ..< 3])
    }

    @Test func scatteredMatchIsMultipleRanges() {
        // "ei" in "engine": 'e'@0, 'i'@3 -> two single-char ranges.
        let ranges = fuzzyHighlightRanges(query: "ei", in: "engine")
        #expect(ranges == [0 ..< 1, 3 ..< 4])
    }

    @Test func caseInsensitive() {
        let ranges = fuzzyHighlightRanges(query: "ENG", in: "Engine")
        #expect(ranges == [0 ..< 3])
    }

    @Test func noMatchIsEmpty() {
        #expect(fuzzyHighlightRanges(query: "zzz", in: "engine").isEmpty)
    }

    @Test func nonFuzzyTokensIgnored() {
        // Only fuzzy tokens contribute; ".png" is an extension token, not fuzzy text.
        #expect(fuzzyHighlightRanges(query: ".png", in: "engine.png").isEmpty)
    }
}
