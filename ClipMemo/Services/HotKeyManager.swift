import Carbon.HIToolbox

/// Global ⌘⇧V summon hotkey via the Carbon RegisterEventHotKey API —
/// no special permission required.
nonisolated final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    private let signature: OSType = 0x434D4347 // 'CMCG'
    private let hotKeyID: UInt32 = 1

    func register(handler: @escaping () -> Void) {
        self.handler = handler
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.hotKeyPressed(event)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hkID = EventHotKeyID(signature: signature, id: hotKeyID)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), hkID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }

    private func hotKeyPressed(_ event: EventRef?) -> OSStatus {
        var hkID = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID) == noErr,
              hkID.signature == signature, hkID.id == hotKeyID else {
            return noErr
        }
        DispatchQueue.main.async { [handler] in handler?() }
        return noErr
    }
}
