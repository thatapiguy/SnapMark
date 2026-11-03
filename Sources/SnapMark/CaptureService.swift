import AppKit
import ScreenCaptureKit

struct DisplayCapture {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    /// Native pixels (e.g. 2x on Retina), sRGB.
    let image: CGImage
}

enum CaptureError: Error {
    case permissionDenied
    case noDisplay
    case failed(Error)
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// ScreenCaptureKit wrapper. `SCShareableContent` is slow on first use (~100-300 ms), so it is
/// fetched ahead of time and cached; the cache is dropped when displays change.
@MainActor
final class CaptureService {
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displays = [:]
                Task { await self?.warmUp() }
            }
        }
    }

    /// Only call when permission is already granted: this is what would otherwise trigger the system prompt.
    func warmUp() async {
        try? await refreshDisplays()
    }

    private func refreshDisplays() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        displays = Dictionary(content.displays.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// One native-resolution frame per connected display, taken as close together as possible.
    func captureAllDisplays() async throws -> [DisplayCapture] {
        let screens = NSScreen.screens.filter { $0.displayID != nil }
        guard !screens.isEmpty else { throw CaptureError.noDisplay }

        do {
            if screens.contains(where: { displays[$0.displayID!] == nil }) {
                try await refreshDisplays()
            }
            let tasks = screens.map { screen in Task { try await self.capture(screen) } }
            var results: [DisplayCapture] = []
            for task in tasks { results.append(try await task.value) }
            return results
        } catch let error as CaptureError {
            throw error
        } catch {
            let ns = error as NSError
            // SCStreamErrorUserDeclined (-3801) is what a missing Screen Recording grant looks like.
            if ns.code == -3801 || !PermissionChecker.isScreenRecordingGranted {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.failed(error)
        }
    }

    private func capture(_ screen: NSScreen) async throws -> DisplayCapture {
        guard let id = screen.displayID, let display = displays[id] else { throw CaptureError.noDisplay }
        let scale = screen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.width = Int((screen.frame.width * scale).rounded())
        config.height = Int((screen.frame.height * scale).rounded())
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return DisplayCapture(screen: screen, displayID: id, image: image)
    }
}
