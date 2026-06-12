import AppKit
import ClingCore

// Modes:
//   ClingApp --render-smoke <fixtureDir> <query> <expectName> <outPNG>   (offscreen render, exits)
//   ClingApp --ui-selftest  <fixtureDir> <query> <expectName> <outPNG>   (drives the LIVE panel)
//   ClingApp                                                             (normal menu-bar agent)
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--render-smoke" {
    guard args.count >= 5 else {
        FileHandle.standardError.write(Data("usage: ClingApp --render-smoke <fixture> <query> <expectName> <outPNG>\n".utf8))
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var ok = false
    let work: @MainActor () -> Void = { ok = RenderSmoke.run(fixture: args[1], query: args[2], expectName: args[3], outPNG: args[4]) }
    if Thread.isMainThread { MainActor.assumeIsolated(work) } else { DispatchQueue.main.sync { MainActor.assumeIsolated(work) } }
    exit(ok ? 0 : 1)
}

if args.first == "--ui-selftest" {
    guard args.count >= 5 else {
        FileHandle.standardError.write(Data("usage: ClingApp --ui-selftest <fixture> <query> <expectName> <outPNG>\n".utf8))
        exit(2)
    }
    // Needs a live run loop: show the real panel, run the async search, assert, then exit.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    MainActor.assumeIsolated {
        DispatchQueue.main.async {
            RenderSmoke.liveSelfTest(fixture: args[1], query: args[2], expectName: args[3], outPNG: args[4]) { passed in
                exit(passed ? 0 : 1)
            }
        }
        // Safety net so the process can never hang the verification run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            FileHandle.standardError.write(Data("selftest: TIMEOUT\n".utf8)); exit(2)
        }
    }
    app.run()
}

// Normal launch.
let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
