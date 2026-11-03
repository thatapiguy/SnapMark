import AppKit
import Carbon.HIToolbox
import SnapMarkCore

/// Global hotkeys via Carbon RegisterEventHotKey: no Accessibility permission needed.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: ((UUID) -> Void)?
    /// Configs whose combo the system refused (usually already taken by another app or macOS).
    private(set) var failedIDs: Set<UUID> = []

    private var refs: [EventHotKeyRef] = []
    private var idsBySlot: [UInt32: UUID] = [:]
    private var handler: EventHandlerRef?
    private var configs: [ShortcutConfig] = []
    private var suspended = false

    private static let signature: OSType = 0x534E4D4B // 'SNMK'

    func register(_ configs: [ShortcutConfig]) {
        self.configs = configs
        unregisterAll()
        guard !suspended else { return }
        installHandlerIfNeeded()

        for (index, config) in configs.enumerated() {
            guard let combo = config.keyCombo, combo.isValidGlobalHotkey else { continue }
            let slot = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
                EventHotKeyID(signature: Self.signature, id: slot),
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                idsBySlot[slot] = config.id
            } else {
                failedIDs.insert(config.id)
            }
        }
    }

    /// The recorder suspends hotkeys so the combo being recorded isn't swallowed by its own registration.
    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        register(configs)
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        idsBySlot.removeAll()
        failedIDs.removeAll()
    }

    fileprivate func handle(slot: UInt32) {
        guard let id = idsBySlot[slot] else { return }
        onTrigger?(id)
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr else { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { manager.handle(slot: hotKeyID.id) } }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    static func carbonModifiers(_ m: KeyCombo.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if m.contains(.command) { result |= UInt32(cmdKey) }
        if m.contains(.shift) { result |= UInt32(shiftKey) }
        if m.contains(.option) { result |= UInt32(optionKey) }
        if m.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
