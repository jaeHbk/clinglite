import Testing
import Foundation

@Suite struct CLITests {
    /// Locate the built `cling` binary next to the test bundle.
    private func clingBinary() -> URL {
        Bundle(for: BundleAnchor.self).bundleURL          // .../ClingLitePackageTests.xctest
            .deletingLastPathComponent()                  // .../debug
            .appendingPathComponent("cling")
    }

    private func run(_ args: [String]) throws -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = clingBinary()
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    @Test func indexThenSearch() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("src/Engine.swift"), atomically: true, encoding: .utf8)
        let idx = root.appendingPathComponent("out.idx")

        let r1 = try run(["index", root.path, idx.path])
        #expect(r1.code == 0)

        let r2 = try run(["search", idx.path, "engine"])
        #expect(r2.code == 0)
        #expect(r2.out.lowercased().contains("engine.swift"))
        try? fm.removeItem(at: root)
    }
}

// Anchor class so Bundle(for:) can locate the test bundle (swift-testing has no XCTestCase).
private final class BundleAnchor {}
