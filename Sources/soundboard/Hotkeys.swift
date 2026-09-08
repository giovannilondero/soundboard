import Carbon
import Foundation

/// Global hotkeys via Carbon RegisterEventHotKey. No Accessibility permission required.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var handler: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x53424452 // "SBDR"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if st == noErr { HotkeyManager.shared.handler?(hk.id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    /// Registers Hyper+key. Returns false if the OS refused (already taken by another app).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32 = KeyCodes.hyper, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let st = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else { return false }
        refs.append(ref)
        return true
    }

    func unregisterAll() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
    }
}
