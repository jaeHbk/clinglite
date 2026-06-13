import Testing
import Foundation
@testable import ClingApp

@Suite struct FileActionsTests {
    private func tempFile() throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Original.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        return (dir, file)
    }

    @Test func renameMovesFileAndReturnsNewPath() throws {
        let (dir, file) = try tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let newPath = FileActions.rename(indexPath: file.path, to: "Renamed.txt")
        #expect(newPath != nil)
        #expect((newPath! as NSString).lastPathComponent == "Renamed.txt")
        #expect(FileManager.default.fileExists(atPath: newPath!))
        #expect(!FileManager.default.fileExists(atPath: file.path))   // old gone
    }

    @Test func renameRejectsCollision() throws {
        let (dir, file) = try tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = dir.appendingPathComponent("Taken.txt")
        try "y".write(to: existing, atomically: true, encoding: .utf8)
        #expect(FileActions.rename(indexPath: file.path, to: "Taken.txt") == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))     // original untouched
    }

    @Test func renameRejectsEmptyAndSlashNames() throws {
        let (dir, file) = try tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FileActions.rename(indexPath: file.path, to: "") == nil)
        #expect(FileActions.rename(indexPath: file.path, to: "   ") == nil)
        #expect(FileActions.rename(indexPath: file.path, to: "a/b.txt") == nil)
    }

    @Test func renameToSameNameIsNoOp() throws {
        let (dir, file) = try tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = FileActions.rename(indexPath: file.path, to: "Original.txt")
        #expect(result == file.path)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
