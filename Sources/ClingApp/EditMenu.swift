import AppKit

/// Installs a standard application main menu with an Edit menu. An LSUIElement agent has no
/// menu by default, so macOS never routes the standard text-editing key equivalents
/// (⌘A select-all, ⌘X cut, ⌘V paste, ⌘Z/⇧⌘Z undo/redo, ⌘Delete, word/line nav) to the focused
/// text field. Adding the Edit menu wires those selectors through the responder chain, so
/// editing the search query works exactly like any native text field.
///
/// Note: ⌘C is intentionally NOT given to the Edit menu's Copy item — the panel's KeyMonitor
/// claims ⌘C for "copy result path" (its more useful meaning while searching) and swallows the
/// event before menu dispatch. All other standard editing shortcuts pass through to this menu.
enum EditMenu {
    /// Assign the standard main menu to the running application.
    static func install() {
        NSApp.mainMenu = makeMainMenu()
    }

    /// Build the main menu (App + Edit) without touching NSApp, so it is unit-testable in a
    /// headless test process where NSApplication isn't fully initialized.
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu (first item) — also provides ⌘Q so Quit works while the panel is key.
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ClingLite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        // Copy item present for completeness, but ⌘C is handled by the panel KeyMonitor
        // (copy result path); leave no key equivalent here so there is no ambiguity.
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        return mainMenu
    }
}
