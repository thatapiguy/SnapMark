import AppKit
import SnapMarkCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let shortcuts = ShortcutsModel()
    private lazy var dispatcher = ActionDispatcher(settings: settings)
    private var statusItem: StatusItemController?
    private var editors: [EditorWindowController] = []
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var openWindowCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuBuilder.build()

        dispatcher.onOpenEditor = { [weak self] image, scale in self?.openEditor(image, scale) }
        dispatcher.onPermissionNeeded = { [weak self] in self?.showOnboarding() }

        HotkeyManager.shared.onTrigger = { [weak self] id in
            guard let self, let config = self.shortcuts.configs.first(where: { $0.id == id }) else { return }
            self.dispatcher.run(config)
        }
        shortcuts.start()

        statusItem = StatusItemController(
            shortcuts: shortcuts,
            onRun: { [weak self] in self?.dispatcher.run($0) },
            onSettings: { [weak self] in self?.showSettings() },
            onPermissions: { [weak self] in self?.showOnboarding() })

        dispatcher.prewarmIfPossible()
        if !settings.hasCompletedOnboarding || !PermissionChecker.isScreenRecordingGranted {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showSettingsAction(_ sender: Any?) { showSettings() }

    // MARK: Windows

    private func openEditor(_ image: CGImage, _ scale: CGFloat) {
        let controller = EditorWindowController(image: image, pixelScale: scale, settings: settings)
        controller.onClose = { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
            self?.windowClosed()
        }
        editors.append(controller)
        present(controller.window!)
    }

    private func showSettings() {
        if let window = settingsWindow {
            present(window)
            return
        }
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SnapMark Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(shortcuts: shortcuts, settings: settings))
        window.center()
        observeClose(of: window) { [weak self] in self?.settingsWindow = nil }
        settingsWindow = window
        present(window)
    }

    private func showOnboarding() {
        if let window = onboardingWindow {
            present(window)
            return
        }
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to SnapMark"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
        })
        window.center()
        observeClose(of: window) { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingWindow = nil
        }
        onboardingWindow = window
        present(window)
    }

    /// Windows need a regular activation policy to take focus and show in ⌘-Tab; revert when all are closed.
    private func present(_ window: NSWindow) {
        openWindowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func windowClosed() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 { NSApp.setActivationPolicy(.accessory) }
    }

    private func observeClose(of window: NSWindow, _ cleanup: @escaping () -> Void) {
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                cleanup()
                self?.windowClosed()
            }
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let main = NSMenu()

        func add(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            holder.submenu = menu
            main.addItem(holder)
        }
        func item(_ title: String, _ action: String, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        add("SnapMark", [
            item("About SnapMark", "orderFrontStandardAboutPanel:"),
            .separator(),
            item("Settings…", "showSettingsAction:", ","),
            .separator(),
            item("Quit SnapMark", "terminate:", "q"),
        ])
        add("File", [
            item("Save", "saveImage:", "s"),
            item("Save As…", "saveImageAs:", "s", [.command, .shift]),
            item("Copy & Close", "copyAndClose:", "\r"),
            .separator(),
            item("Close", "performClose:", "w"),
        ])
        add("Edit", [
            item("Undo", "undo:", "z"),
            item("Redo", "redo:", "z", [.command, .shift]),
            .separator(),
            item("Cut", "cut:", "x"),
            item("Copy", "copy:", "c"),
            item("Paste", "paste:", "v"),
            item("Delete", "delete:"),
            item("Select All", "selectAll:", "a"),
        ])
        add("View", [
            item("Zoom In", "zoomIn:", "="),
            item("Zoom Out", "zoomOut:", "-"),
            item("Fit to Window", "zoomToFit:", "0"),
        ])
        return main
    }
}
