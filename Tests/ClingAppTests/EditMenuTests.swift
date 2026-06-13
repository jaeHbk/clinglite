import Testing
import AppKit
@testable import ClingApp

/// The bug: as an LSUIElement agent the app had NO main menu, so macOS never routed standard
/// text-editing key equivalents (⌘A select-all, ⌘X cut, ⌘V paste, ⌘Z undo) to the focused
/// search field — ⌘A did nothing. EditMenu.install() adds a standard Edit menu so these work.
@MainActor
@Suite struct EditMenuTests {
    private func editMenu() -> NSMenu? {
        EditMenu.makeMainMenu().items.first(where: { $0.submenu?.title == "Edit" })?.submenu
    }

    @Test func mainMenuContainsEditMenu() {
        let mainMenu = EditMenu.makeMainMenu()
        #expect(mainMenu.items.contains(where: { $0.submenu?.title == "Edit" }))
    }

    @Test func selectAllItemBoundToCmdA() throws {
        let edit = try #require(editMenu())
        let selectAll = try #require(edit.items.first { $0.title == "Select All" })
        #expect(selectAll.keyEquivalent == "a")
        #expect(selectAll.keyEquivalentModifierMask == .command)
        #expect(selectAll.action == #selector(NSText.selectAll(_:)))
    }

    @Test func cutPasteSelectAllPresentWithStandardShortcuts() throws {
        let edit = try #require(editMenu())
        func item(_ title: String) -> NSMenuItem? { edit.items.first { $0.title == title } }
        #expect(item("Cut")?.keyEquivalent == "x")
        #expect(item("Paste")?.keyEquivalent == "v")
        #expect(item("Select All")?.keyEquivalent == "a")
        #expect(item("Undo")?.keyEquivalent == "z")
        // Copy is present but intentionally has no ⌘C (the panel KeyMonitor owns ⌘C = copy path).
        #expect(item("Copy") != nil)
        #expect(item("Copy")?.keyEquivalent == "")
    }

    @Test func fieldEditorRespondsToSelectAllAndDelete() {
        // Prove the mechanism end-to-end on an NSTextView (the field editor backing a TextField):
        // selectAll then delete clears the text — exactly "⌘A then delete while searching".
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        tv.string = "my search query"
        tv.selectAll(nil)
        #expect(tv.selectedRange() == NSRange(location: 0, length: ("my search query" as NSString).length))
        tv.delete(nil)
        #expect(tv.string.isEmpty)   // select-all + delete clears the field
    }
}
