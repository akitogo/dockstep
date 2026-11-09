import Carbon.HIToolbox
import Foundation

/// Global keyboard shortcuts via Carbon's `RegisterEventHotKey`.
/// Needs no Accessibility or Input Monitoring permission. Handlers run on the main thread.
final class HotKeys {
    static let shared = HotKeys()

    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1
    private let signature: OSType = 0x444B_5350 // "DKSP"

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hotKeyId = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
            guard status == noErr else { return status }
            HotKeys.shared.fire(hotKeyId.id)
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// Returns an id for `unregister`, or nil if the shortcut is taken.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextId
        nextId += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: signature, id: id),
            GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Dockstep: could not register hotkey keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
            return nil
        }
        refs[id] = ref
        actions[id] = action
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}
