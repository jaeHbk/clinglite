import AppKit
import SwiftUI

/// Borderless floating panel that hosts the SearchView, centered on the active screen, joining
/// all Spaces, hiding when it loses key status.
public final class SearchPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let makeView: () -> AnyView
    public var onHide: () -> Void = {}

    public init(view: @escaping () -> AnyView) { self.makeView = view }

    public func toggle() { (panel?.isVisible ?? false) ? hide() : show() }

    public func show() {
        if panel == nil { build() }
        guard let panel else { return }
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
        onHide()
    }

    private func build() {
        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 80)
        let p = NSPanel(contentRect: hosting.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
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
        p.worksWhenModal = true
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

    // Hide on losing key (click-away / app switch).
    public func windowDidResignKey(_ notification: Notification) { hide() }

    /// Allow a borderless panel to become key (so the text field can receive input).
    public func canBecomeKey() -> Bool { true }
}
