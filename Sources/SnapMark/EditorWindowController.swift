import AppKit
import SnapMarkCore
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let session: EditorSession
    var onClose: ((EditorWindowController) -> Void)?
    private var skipUnsavedPrompt = false

    init(image: CGImage, pixelScale: CGFloat, settings: AppSettings) {
        let document = EditorDocument(baseImage: image, pixelScale: pixelScale)
        session = EditorSession(document: document, settings: settings)

        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "SnapMark — \(image.width) × \(image.height)"
        window.minSize = NSSize(width: 720, height: 360)
        super.init(window: window)

        let root = EditorRootView(
            session: session,
            onCopyAndClose: { [weak self] in self?.copyAndClose(nil) },
            onSave: { [weak self] in self?.saveImage(nil) })
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.delegate = self
        window.setContentSize(Self.initialSize(for: image, scale: pixelScale))
        window.center()
        session.requestClose = { [weak self] in self?.window?.performClose(nil) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func initialSize(for image: CGImage, scale: CGFloat) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let toolbar: CGFloat = 52
        return NSSize(
            width: min(max(CGFloat(image.width) / scale + 40, 760), visible.width * 0.9),
            height: min(max(CGFloat(image.height) / scale + toolbar + 40, 420), visible.height * 0.9))
    }

    // MARK: Menu actions (reach us through the responder chain)

    @objc func copyAndClose(_ sender: Any?) {
        guard session.copyToClipboard() else { NSSound.beep(); return }
        skipUnsavedPrompt = true
        window?.performClose(nil)
    }

    @objc func copy(_ sender: Any?) {
        if !session.copyToClipboard() { NSSound.beep() }
    }

    @objc func saveImage(_ sender: Any?) {
        do { try session.save() } catch { present(error) }
    }

    @objc func saveImageAs(_ sender: Any?) {
        session.canvas?.endTextEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = session.suggestedFileName
        panel.canCreateDirectories = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try self?.session.write(to: url) } catch { self?.present(error) }
        }
    }

    @objc func undo(_ sender: Any?) { session.document.undo() }
    @objc func redo(_ sender: Any?) { session.document.redo() }
    @objc func zoomIn(_ sender: Any?) { session.canvas?.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { session.canvas?.zoom(by: 0.8) }
    @objc func zoomToFit(_ sender: Any?) { session.canvas?.fitToWindow() }
    @objc func delete(_ sender: Any?) { session.deleteSelection() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): session.canUndo
        case #selector(redo(_:)): session.canRedo
        default: true
        }
    }

    private func present(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        session.canvas?.endTextEditing()
        guard session.document.isDirty, !skipUnsavedPrompt else { return true }

        let alert = NSAlert()
        alert.messageText = "Close without saving?"
        alert.informativeText = "This screenshot has edits that haven't been saved or copied."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try session.save(); return true } catch { present(error); return false }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}
