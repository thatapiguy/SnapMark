import AppKit
import SnapMarkCore

struct RegionSelection {
    /// Cropped from the frozen native-resolution frame.
    let image: CGImage
    /// Pixels per point of the display the selection was made on.
    let pixelScale: CGFloat
}

final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One borderless panel per display, each showing a frozen frame of that display.
@MainActor
final class SelectionOverlayController {
    private var panels: [OverlayPanel] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?

    var isActive: Bool { continuation != nil }

    func select(from captures: [DisplayCapture]) async -> RegionSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(captures)
        }
    }

    private func present(_ captures: [DisplayCapture]) {
        let mouse = NSEvent.mouseLocation
        var keyPanel: OverlayPanel?

        for capture in captures {
            let panel = OverlayPanel(screen: capture.screen)
            let view = SelectionView(capture: capture)
            view.onBegin = { [weak self, weak view] in
                guard let view else { return }
                self?.views.filter { $0 !== view }.forEach { $0.setInactive() }
            }
            view.onFinish = { [weak self] selection in self?.finish(selection) }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
            if NSMouseInRect(mouse, capture.screen.frame, false) { keyPanel = panel }
        }
        let target = keyPanel ?? panels.first
        target?.makeKey()
        if let target, let view = target.contentView as? SelectionView {
            target.makeFirstResponder(view)
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ selection: RegionSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for panel in panels {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        continuation.resume(returning: selection)
    }
}

/// Draws the frozen frame, dims it, and lets the user drag a rectangle.
/// Deliberately not flipped: CALayer geometry is simplest in AppKit's native bottom-left space;
/// the selection is converted to top-left only when mapping to image pixels.
final class SelectionView: NSView {
    var onBegin: (() -> Void)?
    var onFinish: ((RegionSelection?) -> Void)?

    private let capture: DisplayCapture
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let loupe: LoupeView

    private var anchor: CGPoint?
    private var selection: CGRect?
    private var isInactive = false

    init(capture: DisplayCapture) {
        self.capture = capture
        self.loupe = LoupeView(image: capture.image)
        super.init(frame: NSRect(origin: .zero, size: capture.screen.frame.size))

        wantsLayer = true
        imageLayer.contents = capture.image
        imageLayer.contentsGravity = .resize
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        borderLayer.isHidden = true
        [imageLayer, dimLayer, borderLayer].forEach { layer?.addSublayer($0) }

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .white
        sizeLabel.drawsBackground = true
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        sizeLabel.alignment = .center
        sizeLabel.isHidden = true
        sizeLabel.setAccessibilityLabel("Selection size")
        addSubview(sizeLabel)
        loupe.isHidden = true
        addSubview(loupe)

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        setAccessibilityLabel("Screenshot region selection. Drag to select, Escape to cancel.")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pixelScale: CGFloat { CGFloat(capture.image.width) / bounds.width }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [imageLayer, dimLayer, borderLayer].forEach { $0.frame = bounds }
        CATransaction.commit()
        updateSelectionVisuals()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let mouse = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        if bounds.contains(mouse) { updateLoupe(at: mouse) }
    }

    func setInactive() {
        isInactive = true
        selection = nil
        loupe.isHidden = true
        updateSelectionVisuals()
    }

    // MARK: Events

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        isInactive = false
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateLoupe(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        anchor = p
        selection = nil
        onBegin?()
        updateLoupe(at: p)
        updateSelectionVisuals()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let p = clamped(convert(event.locationInWindow, from: nil))
        selection = CGRect(from: anchor, to: p)
        updateLoupe(at: p)
        updateSelectionVisuals()
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard let rect = selection, rect.width >= 3, rect.height >= 3 else {
            selection = nil
            updateSelectionVisuals()
            return
        }
        // View space is bottom-left origin; CGImage cropping is top-left.
        let topLeft = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        let pixels = CoordinateMapper.pixelRect(
            forSelection: topLeft, viewSize: bounds.size,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height))
        guard let cropped = capture.image.cropping(to: pixels) else { onFinish?(nil); return }
        onFinish?(RegionSelection(image: cropped, pixelScale: pixelScale))
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }
    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    // MARK: Drawing helpers

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func updateSelectionVisuals() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection { path.addRect(selection) }
        dimLayer.path = path
        dimLayer.fillColor = NSColor.black.withAlphaComponent(isInactive ? 0.55 : 0.4).cgColor

        guard let selection else {
            borderLayer.isHidden = true
            sizeLabel.isHidden = true
            return
        }
        borderLayer.path = CGPath(rect: selection, transform: nil)
        borderLayer.isHidden = false

        let w = Int((selection.width * pixelScale).rounded())
        let h = Int((selection.height * pixelScale).rounded())
        sizeLabel.stringValue = "\(w) × \(h)"
        sizeLabel.setAccessibilityValue("\(w) by \(h) pixels")
        sizeLabel.sizeToFit()
        let labelSize = CGSize(width: sizeLabel.frame.width + 12, height: sizeLabel.frame.height + 4)
        var origin = CGPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + labelSize.height > bounds.height { origin.y = selection.maxY - labelSize.height - 6 }
        origin.x = min(origin.x, bounds.width - labelSize.width)
        sizeLabel.frame = CGRect(origin: origin, size: labelSize)
        sizeLabel.isHidden = false
    }

    private func updateLoupe(at p: CGPoint) {
        guard !isInactive else { return }
        let size = loupe.frame.size
        var origin = CGPoint(x: p.x + 24, y: p.y - 24 - size.height)
        if origin.x + size.width > bounds.width { origin.x = p.x - 24 - size.width }
        if origin.y < 0 { origin.y = p.y + 24 }
        loupe.frame.origin = origin

        let s = pixelScale
        loupe.pixel = CGPoint(
            x: min(max(floor(p.x * s), 0), CGFloat(capture.image.width - 1)),
            y: min(max(floor((bounds.height - p.y) * s), 0), CGFloat(capture.image.height - 1)))
        loupe.isHidden = false
        loupe.needsDisplay = true
    }
}

/// Magnifier showing the pixels under the cursor from the frozen frame.
final class LoupeView: NSView {
    private let image: CGImage
    /// Image pixel under the cursor, top-left origin.
    var pixel: CGPoint = .zero

    private let zoom: CGFloat = 9

    init(image: CGImage) {
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: 126, height: 126))
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let circle = bounds.insetBy(dx: 2, dy: 2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        ctx.interpolationQuality = .none
        // Place the cursor pixel's center at the loupe center.
        let w = CGFloat(image.width) * zoom, h = CGFloat(image.height) * zoom
        let x0 = center.x - (pixel.x + 0.5) * zoom
        let y0 = center.y - h + (pixel.y + 0.5) * zoom
        ctx.draw(image, in: CGRect(x: x0, y: y0, width: w, height: h))
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circle)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: center.x - zoom / 2, y: center.y - zoom / 2, width: zoom, height: zoom))

        let text = "\(Int(pixel.x)), \(Int(pixel.y))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: 14), withAttributes: attrs)
    }
}
