import AppKit
import SwiftUI
import ClingCore

/// Wires the menu-bar agent: builds the index coordinator, search controller, panel, hotkey,
/// key monitor, FS watcher, and menu bar. LSUIElement (accessory) by default.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig()
    private var coordinator: IndexCoordinator!
    private var controller: SearchController!
    private var panel: SearchPanel!
    private var hotKey = HotKey()
    private var keyMonitor = KeyMonitor()
    private var fsWatcher: FSWatcher!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(config.showDockIcon ? .regular : .accessory)
        EditMenu.install()   // standard Edit menu => ⌘A/⌘X/⌘V/⌘Z work in the search field

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClingLite", isDirectory: true)
        coordinator = IndexCoordinator(storeDirectory: appSupport, ignorePatterns: AppConfig.defaultIgnorePatterns)
        coordinator.loadExisting(roots: config.roots)        // instant search on existing/just-built index
        controller = SearchController(service: coordinator.service, maxResults: config.maxResults)

        menuBar = MenuBarController()
        menuBar.onShow = { [weak self] in self?.panel.show() }
        menuBar.onReindex = { [weak self] in self?.reindexAll() }
        menuBar.onSettings = { [weak self] in self?.openSettings() }
        menuBar.onQuit = { NSApp.terminate(nil) }

        panel = SearchPanel(controller: controller,
                            onSubmit: { [weak self] in self?.openSelected() },
                            onReveal: { [weak self] in self?.revealSelected() })
        panel.onHide = { [weak self] in self?.coordinator.service.adviseDontNeedAll() }

        keyMonitor.onMove = { [weak self] d in self?.controller.moveSelection(d) }
        keyMonitor.onOpen = { [weak self] in self?.openSelected() }
        keyMonitor.onReveal = { [weak self] in self?.revealSelected() }
        keyMonitor.onQuickLook = { [weak self] in self?.revealSelected() } // QL falls back to reveal in B2
        keyMonitor.onCopyPath = { [weak self] in if let p = self?.controller.selectedRow?.path { FileActions.copyPath(p) } }
        keyMonitor.onOpenTerminal = { [weak self] in
            guard let row = self?.controller.selectedRow else { return }
            FileActions.openInTerminal(row.path, isDir: row.isDir)
        }
        keyMonitor.onRename = { [weak self] in self?.renameSelected() }
        keyMonitor.onEscape = { [weak self] in self?.panel.hide() }
        keyMonitor.start()

        hotKey.onPressed = { [weak self] in self?.panel.toggle() }
        hotKey.register(keyCode: config.hotKeyKeyCode, nsModifiers: config.hotKeyModifiers)

        fsWatcher = FSWatcher(service: coordinator.service, roots: config.roots)
        fsWatcher.start()

        // Kick a background refresh so the index is current shortly after launch.
        Diag.log("[launch] reindexAll started for roots=\(config.roots)")
        coordinator.reindexAll(roots: config.roots) { [weak self] in
            Diag.log("[reindex] base swap COMPLETE (index now fresh)")
            DispatchQueue.main.async { self?.menuBar.rebuildMenu(status: "Indexed \(self?.config.roots.count ?? 0) root(s)") }
        }
    }

    private func openSelected() {
        guard let row = controller.selectedRow else { return }
        FileActions.open(row.path); panel.hide()
    }
    private func revealSelected() {
        guard let row = controller.selectedRow else { return }
        FileActions.revealInFinder(row.path); panel.hide()
    }
    private func renameSelected() {
        guard let row = controller.selectedRow else { return }
        let oldPath = row.path
        let oldIsDir = row.isDir
        panel.hide()   // free the borderless panel's key focus before showing a modal
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \"\(row.name)\"."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = row.name
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let newReal = FileActions.rename(indexPath: oldPath, to: field.stringValue) else {
            let warn = NSAlert()
            warn.messageText = "Rename failed"
            warn.informativeText = "The name may be empty, contain a '/', or already exist."
            warn.runModal()
            return
        }
        // Reflect the change in the live index, then re-run the current query.
        coordinator.service.applyChange(path: oldPath, exists: false, isDir: oldIsDir)
        coordinator.service.applyChange(path: newReal, exists: true, isDir: oldIsDir)
        controller.refresh()
    }
    private func reindexAll() {
        menuBar.rebuildMenu(status: "Indexing…")
        coordinator.reindexAll(roots: config.roots) { [weak self] in
            DispatchQueue.main.async { self?.menuBar.rebuildMenu(status: "Ready") }
        }
    }
    private func openSettings() {
        if settingsWindow == nil {
            let v = SettingsView(roots: config.roots, maxResults: Double(config.maxResults),
                                 showDockIcon: config.showDockIcon,
                                 onSave: { [weak self] roots, mr, dock in self?.saveSettings(roots, mr, dock) },
                                 onAddRoot: { Self.chooseFolder() })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "ClingLite Settings"
            w.contentView = NSHostingView(rootView: v)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func saveSettings(_ roots: [String], _ mr: Int, _ dock: Bool) {
        config.roots = roots; config.maxResults = mr; config.showDockIcon = dock; config.save()
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
        settingsWindow?.close(); settingsWindow = nil
        coordinator.loadExisting(roots: roots)
        reindexAll()
    }
    private static func chooseFolder() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url?.path : nil
    }
}
