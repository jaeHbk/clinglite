import AppKit
import SwiftUI

/// A borderless NSPanel that CAN become key/main. AppKit reads `canBecomeKey`/`canBecomeMain`
/// on the window object itself, so a borderless panel must override them here (a delegate
/// method is never consulted) — otherwise the hosted SwiftUI TextField never receives focus.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Borderless floating panel that hosts the SearchView, centered on the active screen, joining
/// all Spaces, hiding when it loses key status.
public final class SearchPanel: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private let makeView: () -> AnyView
    public var onHide: () -> Void = {}
    private var suppressResignHide = false   // guards resign during programmatic hide

    public init(view: @escaping () -> AnyView) { self.makeView = view }

    public func toggle() { (panel?.isVisible ?? false) ? hide() : show() }

    public func show() {
        if panel == nil { build() }
        guard let panel else { return }
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Put the keyboard focus into the SwiftUI text field (first key view in the hosting view).
        panel.makeFirstResponder(panel.contentView)
    }

    public func hide() {
        guard let panel, panel.isVisible else { onHide(); return }
        suppressResignHide = true
        panel.orderOut(nil)
        suppressResignHide = false
        onHide()
    }

    private func build() {
        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 80)
        // No `.nonactivatingPanel`: that style prevents the panel from becoming key, which would
        // stop the text field from receiving input. We want the panel to activate and take focus.
        let p = KeyablePanel(contentRect: hosting.frame,
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hosting
        p.delegate = self
        p.hidesOnDeactivate = false
        panel = p
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let size = panel.frame.size
        let x = sf.midX - size.width / 2
        let y = sf.midY + sf.height * 0.15 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Hide on losing key (click-away / app switch), except during our own programmatic hide.
    public func windowDidResignKey(_ notification: Notification) {
        if suppressResignHide { return }
        hide()
    }
}
