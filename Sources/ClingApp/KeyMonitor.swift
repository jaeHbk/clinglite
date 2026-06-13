import AppKit

/// Local NSEvent monitor for the search panel's key commands. Returns nil to swallow the event
/// when handled (so the text field doesn't also process arrows/enter/esc).
public final class KeyMonitor {
    public var onMove: (Int) -> Void = { _ in }
    public var onOpen: () -> Void = {}
    public var onReveal: () -> Void = {}
    public var onQuickLook: () -> Void = {}
    public var onCopyPath: () -> Void = {}
    public var onOpenTerminal: () -> Void = {}
    public var onRename: () -> Void = {}
    public var onEscape: () -> Void = {}

    private var monitor: Any?

    public func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 125: self.onMove(1); return nil    // down arrow
            case 126: self.onMove(-1); return nil   // up arrow
            case 36, 76:                            // return / keypad enter
                if cmd { self.onReveal() } else { self.onOpen() }; return nil
            case 16 where cmd: self.onQuickLook(); return nil  // cmd-y -> quick look
            case 17 where cmd: self.onOpenTerminal(); return nil  // cmd-t -> open dir in Terminal
            case 15 where cmd: self.onRename(); return nil        // cmd-r -> rename
            case 53: self.onEscape(); return nil    // escape
            case 8 where cmd: self.onCopyPath(); return nil  // cmd-c
            default: return event
            }
        }
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
