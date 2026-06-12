import Testing
@testable import ClingCore

@Suite struct ScaffoldTests {
    @Test func versionPresent() {
        #expect(!ClingCore.version.isEmpty)
    }
}
