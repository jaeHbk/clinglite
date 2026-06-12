import Testing
import Foundation
@testable import ClingCore

@Suite struct MemoryHarnessTests {
    @Test func residentBytesIsPositive() {
        #expect(currentResidentBytes() > 0)
    }
}
