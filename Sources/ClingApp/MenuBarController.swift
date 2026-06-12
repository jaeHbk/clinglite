import AppKit

/// Menu-bar status item with the app's commands. Pure AppKit; actions are injected closures.
public final class MenuBarController {
    private let statusItem: NSStatusItem
    public var onShow: () -> Void = {}
    public var onReindex: () -> Void = {}
    public var onSettings: () -> Void = {}
    public var onQuit: () -> Void = {}

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "ClingLite")
        }
        rebuildMenu(status: "Ready")
    }

    public func rebuildMenu(status: String) {
        let menu = NSMenu()
        let statusRow = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Search…", action: #selector(fireShow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reindex Now", action: #selector(fireReindex), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(fireSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClingLite", action: #selector(fireQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func fireShow() { onShow() }
    @objc private func fireReindex() { onReindex() }
    @objc private func fireSettings() { onSettings() }
    @objc private func fireQuit() { onQuit() }
}
