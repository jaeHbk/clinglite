import Foundation

/// Lightweight opt-in diagnostic log (gated by the CLINGLITE_DIAG=1 env var) used to
/// investigate the "preview vs list mismatch that self-corrects after N interactions" report.
/// Appends timestamped lines to /tmp/clinglite-diag.log. Zero cost when disabled.
enum Diag {
    static let enabled = ProcessInfo.processInfo.environment["CLINGLITE_DIAG"] == "1"
    private static let url = URL(fileURLWithPath: "/tmp/clinglite-diag.log")
    private static let lock = NSLock()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = message() + "\n"
        lock.lock(); defer { lock.unlock() }
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
