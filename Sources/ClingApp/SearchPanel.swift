import AppKit
import SwiftUI

/// A borderless NSPanel that CAN become key/main. AppKit reads `canBecomeKey`/`canBecomeMain`
/// on the window object itself, so a borderless panel must override them here (a delegate
/// method is never consulted) — otherwise the hosted SwiftUI TextField never receives focus.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Borderless floating panel hosting the SearchView. Owns the SwiftUI root so it can drive a
/// focus tick (re-focus the field on every show) and resize the window to fit results.
public final class SearchPanel: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private var hosting: NSHostingView<AnyView>?
    private let controller: SearchController
    private let onSubmit: () -> Void
    private let onReveal: () -> Void
    public var onHide: () -> Void = {}

    private var focusTick = 0
    private var currentHeight: CGFloat = PanelLayout.searchBarHeight
    private var suppressResignHide = false

    public init(controller: SearchController, onSubmit: @escaping () -> Void, onReveal: @escaping () -> Void) {
        self.controller = controller
        self.onSubmit = onSubmit
        self.onReveal = onReveal
        super.init()
    }

    public func toggle() { (panel?.isVisible ?? false) ? hide() : show() }

    public func show() {
        if panel == nil { build() }
        guard let panel else { return }
        focusTick &+= 1
        rebuildRoot()                       // re-render with the new focusTick to focus the field
        resize(toHeight: currentHeight, recenter: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        guard let panel, panel.isVisible else { onHide(); return }
        suppressResignHide = true
        panel.orderOut(nil)
        suppressResignHide = false
        onHide()
    }

    private func rootView() -> AnyView {
        AnyView(
            SearchView(
                controller: controller,
                focusTick: focusTick,
                onSubmit: onSubmit,
                onReveal: onReveal,
                onHeightChange: { [weak self] h in self?.resize(toHeight: h, recenter: true) }
            )
        )
    }

    private func rebuildRoot() { hosting?.rootView = rootView() }

    private func build() {
        let host = NSHostingView(rootView: rootView())
        host.frame = NSRect(x: 0, y: 0, width: PanelLayout.width, height: currentHeight)
        let p = KeyablePanel(contentRect: host.frame,
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = host
        p.delegate = self
        p.hidesOnDeactivate = false
        panel = p
        hosting = host
    }

    /// Resize the panel to a new content height, keeping it anchored near the top of the screen
    /// so the search bar doesn't jump as results appear/disappear.
    public func resize(toHeight height: CGFloat, recenter: Bool) {
        currentHeight = height
        guard let panel else { return }
        let topY = panel.frame.maxY
        var frame = panel.frame
        frame.size.width = PanelLayout.width
        frame.size.height = height
        if recenter, let screen = NSScreen.main, !panel.isVisible {
            let sf = screen.visibleFrame
            frame.origin.x = sf.midX - PanelLayout.width / 2
            frame.origin.y = sf.midY + sf.height * 0.18 - height / 2
        } else {
            // Keep the top edge fixed; grow downward.
            frame.origin.y = topY - height
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    /// The live window's content height — used by verification to confirm it grew with results.
    public var windowHeight: CGFloat { panel?.frame.height ?? 0 }
    /// Whether the current first responder is a text-editing view (focus actually landed).
    public var fieldHasFocus: Bool {
        guard let r = panel?.firstResponder else { return false }
        return r is NSTextView || (r as? NSView)?.className.contains("Text") == true
    }

    public func windowDidResignKey(_ notification: Notification) {
        if suppressResignHide { return }
        hide()
    }
}
