import AppKit
import SnapMarkCore
import SwiftUI

/// Click, then press a combination. Esc cancels, ⌫ clears.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { context.coordinator.set($0) }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        context.coordinator.parent = self
        button.combo = combo
        button.onChange = { context.coordinator.set($0) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator {
        var parent: ShortcutRecorder
        init(parent: ShortcutRecorder) { self.parent = parent }
        func set(_ combo: KeyCombo?) { parent.combo = combo }
    }
}

final class RecorderButton: NSButton {
    var onChange: ((KeyCombo?) -> Void)?
    var combo: KeyCombo? { didSet { refreshTitle() } }
    private var monitor: Any?
    private var isRecording = false { didSet { refreshTitle() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggle)
        setAccessibilityLabel("Keyboard shortcut recorder")
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : (combo?.displayString ?? "Record Shortcut")
        setAccessibilityValue(combo?.displayString ?? "none")
    }

    @objc private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        MainActor.assumeIsolated { HotkeyManager.shared.setSuspended(true) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        MainActor.assumeIsolated { HotkeyManager.shared.setSuspended(false) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case 53: // Esc
            stop()
            return nil
        case 51, 117: // Delete
            stop()
            onChange?(nil)
            return nil
        default:
            var m: KeyCombo.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.command) { m.insert(.command) }
            if flags.contains(.shift) { m.insert(.shift) }
            if flags.contains(.option) { m.insert(.option) }
            if flags.contains(.control) { m.insert(.control) }
            let candidate = KeyCombo(keyCode: Int(event.keyCode), modifiers: m)
            guard candidate.isValidGlobalHotkey else { NSSound.beep(); return nil }
            stop()
            onChange?(candidate)
            return nil
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
