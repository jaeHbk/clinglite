import Testing
import Foundation
@testable import ClingApp

@Suite struct AppConfigTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "clinglite.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsWhenUnset() {
        let cfg = AppConfig(defaults: freshDefaults())
        #expect(cfg.roots == [NSHomeDirectory()])      // default root = home
        #expect(cfg.maxResults == 100)
        #expect(cfg.showDockIcon == false)             // menu-bar agent by default
        #expect(cfg.hotKeyKeyCode == 49)               // Space
        #expect(cfg.hotKeyModifiers == 524288)          // option (NSEvent.ModifierFlags.option.rawValue)
    }

    @Test func roundTripsThroughDefaults() {
        let d = freshDefaults()
        var cfg = AppConfig(defaults: d)
        cfg.roots = ["/tmp/a", "/tmp/b"]
        cfg.maxResults = 42
        cfg.showDockIcon = true
        cfg.hotKeyKeyCode = 3
        cfg.hotKeyModifiers = 1048576
        cfg.save()
        let reloaded = AppConfig(defaults: d)
        #expect(reloaded.roots == ["/tmp/a", "/tmp/b"])
        #expect(reloaded.maxResults == 42)
        #expect(reloaded.showDockIcon == true)
        #expect(reloaded.hotKeyKeyCode == 3)
        #expect(reloaded.hotKeyModifiers == 1048576)
    }
}
