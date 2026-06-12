import Testing
import Foundation
@testable import ClingApp

@Suite struct FilePreviewInfoTests {
    @Test func humanSizeFormatting() {
        #expect(FilePreviewInfo.humanSize(0) == "0 B")
        #expect(FilePreviewInfo.humanSize(512) == "512 B")
        #expect(FilePreviewInfo.humanSize(1024) == "1.0 KB")
        #expect(FilePreviewInfo.humanSize(1536) == "1.5 KB")
        #expect(FilePreviewInfo.humanSize(1024 * 1024) == "1.0 MB")
        #expect(FilePreviewInfo.humanSize(20 * 1024 * 1024) == "20 MB")
    }

    @Test func realFileMetadata() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fpi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Report.pdf")
        try Data(repeating: 0, count: 2048).write(to: file)

        let info = FilePreviewInfo(indexPath: file.path.lowercased(), isDir: false)
        #expect(info.name.lowercased() == "report.pdf")
        #expect(info.kind == "pdf")
        #expect(info.sizeText == "2.0 KB")
        #expect(info.modifiedText != "—")          // a real mtime was read
        #expect(info.isDir == false)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func directoryMetadata() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fpidir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let info = FilePreviewInfo(indexPath: dir.path.lowercased(), isDir: true)
        #expect(info.kind == "Folder")
        #expect(info.sizeText == "—")
        try? FileManager.default.removeItem(at: dir)
    }
}
