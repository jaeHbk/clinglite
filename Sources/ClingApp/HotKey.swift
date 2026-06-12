import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon RegisterEventHotKey (no Accessibility permission
/// required). Invokes `onPressed` on the main thread when the combo fires.
public final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    public var onPressed: () -> Void = {}

    private static var shared: HotKey?

    public init() {}

    /// keyCode is a virtual key code (e.g. 49 = Space). carbonModifiers built from NSEvent flags.
    public func register(keyCode: Int, nsModifiers: Int) {
        unregister()
        HotKey.shared = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            HotKey.shared?.onPressed()
            return noErr
        }, 1, &eventType, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4E47), id: 1) // 'CLNG'
        let carbonMods = HotKey.carbonFlags(fromNS: nsModifiers)
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    public func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    private static func carbonFlags(fromNS ns: Int) -> UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: UInt(ns))
        var c: UInt32 = 0
        if f.contains(.command) { c |= UInt32(cmdKey) }
        if f.contains(.option)  { c |= UInt32(optionKey) }
        if f.contains(.control) { c |= UInt32(controlKey) }
        if f.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }
}
