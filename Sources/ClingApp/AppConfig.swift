import Foundation

/// User settings persisted in UserDefaults. Plain struct; `save()` writes all fields.
public struct AppConfig {
    private let defaults: UserDefaults
    private enum Key {
        static let roots = "roots"
        static let maxResults = "maxResults"
        static let showDockIcon = "showDockIcon"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }

    public var roots: [String]
    public var maxResults: Int
    public var showDockIcon: Bool
    public var hotKeyKeyCode: Int
    public var hotKeyModifiers: Int

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.roots = (defaults.array(forKey: Key.roots) as? [String]) ?? [NSHomeDirectory()]
        let mr = defaults.integer(forKey: Key.maxResults)
        self.maxResults = mr == 0 ? 100 : mr
        self.showDockIcon = defaults.bool(forKey: Key.showDockIcon)   // default false
        let kc = defaults.object(forKey: Key.hotKeyKeyCode) as? Int
        self.hotKeyKeyCode = kc ?? 49                                  // Space
        let mods = defaults.object(forKey: Key.hotKeyModifiers) as? Int
        self.hotKeyModifiers = mods ?? 524288                          // Option
    }

    public func save() {
        defaults.set(roots, forKey: Key.roots)
        defaults.set(maxResults, forKey: Key.maxResults)
        defaults.set(showDockIcon, forKey: Key.showDockIcon)
        defaults.set(hotKeyKeyCode, forKey: Key.hotKeyKeyCode)
        defaults.set(hotKeyModifiers, forKey: Key.hotKeyModifiers)
    }

    /// Default ignore patterns applied to every root.
    public static let defaultIgnorePatterns = [
        ".git/", "node_modules/", ".build/", "DerivedData/", ".Trash/",
        "Library/Caches/", ".DS_Store", "*.o",
    ]
}
