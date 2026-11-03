import AppKit
import SnapMarkCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let shortcuts: ShortcutsModel
    private let onRun: (ShortcutConfig) -> Void
    private let onSettings: () -> Void
    private let onPermissions: () -> Void

    init(shortcuts: ShortcutsModel,
         onRun: @escaping (ShortcutConfig) -> Void,
         onSettings: @escaping () -> Void,
         onPermissions: @escaping () -> Void) {
        self.shortcuts = shortcuts
        self.onRun = onRun
        self.onSettings = onSettings
        self.onPermissions = onPermissions
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapMark")
            button.setAccessibilityLabel("SnapMark")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for config in shortcuts.configs {
            let item = NSMenuItem(title: config.summary, action: #selector(runShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = config.id
            if let combo = config.keyCombo { item.title += "    \(combo.displayString)" }
            menu.addItem(item)
        }
        if shortcuts.configs.isEmpty {
            let empty = NSMenuItem(title: "No shortcuts — add one in Settings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Screen Recording Permission…", #selector(openPermissions), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit SnapMark", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func runShortcut(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let config = shortcuts.configs.first(where: { $0.id == id }) else { return }
        // Let the menu finish closing so it isn't captured into the frozen frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.onRun(config) }
    }

    @objc private func openSettings() { onSettings() }
    @objc private func openPermissions() { onPermissions() }
}
