import AppKit
import CoreGraphics

enum PermissionChecker {
    /// Note: false means "not granted" — macOS gives no way to tell "never asked" from "denied".
    static var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openKeyboardShortcutsSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// macOS often needs the app restarted before a fresh Screen Recording grant takes effect.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
