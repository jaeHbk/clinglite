import Testing
import Foundation
@testable import ClingApp

@Suite struct PathResolverTests {
    @Test func resolvesExactExistingPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        // The exact path exists -> returned as-is.
        let resolved = PathResolver.resolve(file.path)
        #expect(resolved == file.path)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func recoversCaseForMismatchedComponent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("MixedCase.TXT")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        // Look up the lowercased form; resolver must recover the real cased name (on a
        // case-insensitive FS the lowercased path may even open directly, but resolve()
        // must return a path that points at the real file either way).
        let lowered = dir.path + "/mixedcase.txt"
        let resolved = PathResolver.resolve(lowered)
        #expect(FileManager.default.fileExists(atPath: resolved))
        #expect((resolved as NSString).lastPathComponent.lowercased() == "mixedcase.txt")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func returnsInputWhenNothingExists() {
        let p = "/nonexistent-\(UUID().uuidString)/whatever.txt"
        #expect(PathResolver.resolve(p) == p)
    }
}
