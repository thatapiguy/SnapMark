import AppKit
import os
import SnapMarkCore

/// Routes a hotkey (capture mode + action) through capture and delivers the result.
@MainActor
final class ActionDispatcher {
    private let capture = CaptureService()
    private let overlay = SelectionOverlayController()
    private let settings: AppSettings
    private let log = Logger(subsystem: "com.snapmark.app", category: "perf")
    private var busy = false

    var onOpenEditor: ((CGImage, CGFloat) -> Void)?
    var onPermissionNeeded: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func prewarmIfPossible() {
        guard PermissionChecker.isScreenRecordingGranted else { return }
        Task { await capture.warmUp() }
    }

    func run(_ config: ShortcutConfig) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            switch config.mode {
            case .region: await captureRegion(then: config.action)
            default: NSSound.beep() // other modes land in Phase 2
            }
        }
    }

    private func captureRegion(then action: AfterCaptureAction) async {
        let start = ContinuousClock.now
        do {
            let frames = try await capture.captureAllDisplays()
            log.info("hotkey→overlay-ready: \(start.duration(to: .now).formatted(), privacy: .public)")
            guard let selection = await overlay.select(from: frames) else { return }
            deliver(selection, action: action)
            log.info("hotkey→delivered: \(start.duration(to: .now).formatted(), privacy: .public)")
        } catch CaptureError.permissionDenied {
            onPermissionNeeded?()
        } catch {
            showError("Capture failed", detail: error.localizedDescription)
        }
    }

    private func deliver(_ selection: RegionSelection, action: AfterCaptureAction) {
        let image = selection.image, scale = selection.pixelScale
        switch action {
        case .copy:
            ClipboardWriter.write(image, pixelScale: scale)
        case .editor:
            onOpenEditor?(image, scale)
        case .save:
            save(image, scale)
        case .copyAndSave:
            ClipboardWriter.write(image, pixelScale: scale)
            save(image, scale)
        case .thumbnail:
            ClipboardWriter.write(image, pixelScale: scale) // Phase 2
        }
    }

    private func save(_ image: CGImage, _ scale: CGFloat) {
        do { try settings.saveImage(image, pixelScale: scale) }
        catch { showError("Couldn't save screenshot", detail: error.localizedDescription) }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
