import AppKit
import ClingCore

// Modes:
//   ClingApp --render-smoke <fixtureDir> <query> <expectName> <outPNG>
//   ClingApp                       (normal menu-bar agent launch)
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--render-smoke" {
    guard args.count >= 5 else {
        FileHandle.standardError.write(Data("usage: ClingApp --render-smoke <fixture> <query> <expectName> <outPNG>\n".utf8))
        exit(2)
    }
    // Render must run on the main thread with an app context.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var ok = false
    let work: @MainActor () -> Void = { ok = RenderSmoke.run(fixture: args[1], query: args[2], expectName: args[3], outPNG: args[4]) }
    if Thread.isMainThread { MainActor.assumeIsolated(work) } else { DispatchQueue.main.sync { MainActor.assumeIsolated(work) } }
    exit(ok ? 0 : 1)
}

// Normal launch.
let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
