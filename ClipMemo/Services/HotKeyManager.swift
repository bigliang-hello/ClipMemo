import Carbon.HIToolbox

/// Global summon hotkeys via the Carbon RegisterEventHotKey API —
/// no special permission required.
nonisolated final class HotKeyManager {

    static let shared = HotKeyManager()

    private struct Registration {
        var ref: EventHotKeyRef
        var handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?

    private let signature: OSType = 0x434D4347 // 'CMCG'

    /// Registers a system-wide hotkey; `id` tells the entries apart in the
    /// shared event callback.
    func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        guard registrations[id] == nil else { return }
        installHandlerIfNeeded()

        let hkID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID,
                                  GetApplicationEventTarget(), 0, &ref) == noErr, let ref else { return }
        registrations[id] = Registration(ref: ref, handler: handler)
    }

    func unregister() {
        for entry in registrations.values { UnregisterEventHotKey(entry.ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        registrations.removeAll()
        eventHandler = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.hotKeyPressed(event)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func hotKeyPressed(_ event: EventRef?) -> OSStatus {
        var hkID = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID) == noErr,
              hkID.signature == signature,
              let entry = registrations[hkID.id] else {
            return noErr
        }
        let handler = entry.handler
        DispatchQueue.main.async { handler() }
        return noErr
    }
}
