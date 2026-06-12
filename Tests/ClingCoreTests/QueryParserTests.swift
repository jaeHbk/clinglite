import Testing
@testable import ClingCore

@Suite struct QueryParserTests {
    @Test func parsesTokenTypes() {
        let q = ParsedQuery(".png in:/Users/me icon depth:3 src/")
        #expect(q.extTokens == ["png"])
        #expect(q.folderPrefixes == ["/users/me"])
        #expect(q.dirSegments == ["src/"])
        #expect(q.depth == 3)
        #expect(q.fuzzyTokens == ["icon"])
    }

    @Test func combinedMaskIsSupersetOfFuzzy() {
        let q = ParsedQuery("abc")
        let m = Array("abc".utf8).withUnsafeBufferPointer { letterMaskBytes($0) }
        #expect(q.combinedMask & m == m)
    }

    @Test func emptyQuery() {
        let q = ParsedQuery("   ")
        #expect(q.isEmpty)
    }
}
