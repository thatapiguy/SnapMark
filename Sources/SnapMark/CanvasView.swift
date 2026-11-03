import AppKit
import SnapMarkCore

/// Keeps a small document centered inside the scroll view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}

final class AnnotationTextView: NSTextView {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The editing surface. View space = image points (flipped, top-left origin); annotation space = image
/// pixels, so every drawing/hit-test converts through `pixelScale`. Zoom is the scroll view's magnification.
@MainActor
final class CanvasView: NSView, NSTextViewDelegate {
    private unowned let session: EditorSession
    private var document: EditorDocument { session.document }
    private var scale: CGFloat { document.pixelScale }

    private enum Interaction {
        case creating(UUID)
        case moving(UUID, last: CGPoint)
        case resizing(UUID, Handle)
        case cropNew(origin: CGPoint)
        case cropResize(Handle)
    }
    private var interaction: Interaction?

    private var textView: AnnotationTextView?
    private var editing: Annotation?
    private var editingIsNew = false

    init(session: EditorSession) {
        self.session = session
        let doc = session.document
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: CGFloat(doc.baseImage.width) / doc.pixelScale,
            height: CGFloat(doc.baseImage.height) / doc.pixelScale))
        setAccessibilityLabel("Screenshot canvas")
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }

    func documentDidChange() { needsDisplay = true }

    func toolDidChange() {
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: session.tool == .select ? .arrow : .crosshair)
    }

    // MARK: Zoom

    func zoom(by factor: CGFloat) {
        guard let sv = enclosingScrollView else { return }
        let target = min(max(sv.magnification * factor, sv.minMagnification), sv.maxMagnification)
        sv.setMagnification(target, centeredAt: NSPoint(x: visibleRect.midX, y: visibleRect.midY))
    }

    func fitToWindow() {
        guard let sv = enclosingScrollView else { return }
        let available = sv.contentSize
        guard available.width > 0, available.height > 0 else { return }
        let fit = min(available.width / bounds.width, available.height / bounds.height)
        sv.magnification = min(1, fit)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let base = document.baseImage

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(base, in: bounds)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        AnnotationRenderer.draw(document.state.annotations, in: ctx, base: base, scale: scale, skipping: editing?.id)
        ctx.restoreGState()

        if let crop = document.state.cropRect { drawCropOverlay(crop, in: ctx) }
        if editing == nil, let id = session.selectedID, let a = document.annotation(id: id) {
            drawHandles(for: a, in: ctx)
        }
    }

    private func drawCropOverlay(_ crop: CGRect, in ctx: CGContext) {
        let rect = CGRect(x: crop.minX / scale, y: crop.minY / scale, width: crop.width / scale, height: crop.height / scale)
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(rect)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1 / magnification)
        ctx.stroke(rect)
        ctx.restoreGState()
        if session.tool == .crop {
            for h in Handle.corners { drawHandleSquare(at: h.position(in: crop), in: ctx) }
        }
    }

    private func drawHandles(for a: Annotation, in ctx: CGContext) {
        if a.kind == .text {
            let b = a.bounds
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1 / magnification)
            ctx.setLineDash(phase: 0, lengths: [4 / magnification, 3 / magnification])
            ctx.stroke(CGRect(x: b.minX / scale, y: b.minY / scale, width: b.width / scale, height: b.height / scale))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        for (_, point) in a.handles { drawHandleSquare(at: point, in: ctx) }
    }

    private func drawHandleSquare(at pixel: CGPoint, in ctx: CGContext) {
        let side = 9 / magnification
        let r = CGRect(x: pixel.x / scale - side / 2, y: pixel.y / scale - side / 2, width: side, height: side)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5 / magnification)
        ctx.stroke(r)
    }

    // MARK: Hit testing (all in image pixels)

    private var handleTolerance: CGFloat { 9 / magnification * scale }
    private var hitTolerance: CGFloat { 6 / magnification * scale }

    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func clampedToImage(_ p: CGPoint) -> CGPoint {
        let b = document.imageBounds
        return CGPoint(x: min(max(p.x, b.minX), b.maxX), y: min(max(p.y, b.minY), b.maxY))
    }

    private func annotationHit(at p: CGPoint) -> Annotation? {
        document.state.annotations.last { $0.hitTest(p, tolerance: hitTolerance) }
    }

    private func selectedHandleHit(at p: CGPoint) -> (UUID, Handle)? {
        guard let id = session.selectedID, let a = document.annotation(id: id) else { return nil }
        for (handle, point) in a.handles where hypot(point.x - p.x, point.y - p.y) <= handleTolerance {
            return (id, handle)
        }
        return nil
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self) // commits any in-progress text edit
        let p = pixelPoint(event)

        switch session.tool {
        case .select:
            if let (id, handle) = selectedHandleHit(at: p) {
                document.beginGesture()
                interaction = .resizing(id, handle)
            } else if let hit = annotationHit(at: p) {
                session.select(hit.id)
                if event.clickCount == 2, hit.kind == .text {
                    beginTextEditing(existing: hit)
                } else {
                    document.beginGesture()
                    interaction = .moving(hit.id, last: p)
                }
            } else {
                session.select(nil)
            }

        case .arrow, .rectangle, .pixelate:
            let kind: AnnotationKind = session.tool == .arrow ? .arrow : (session.tool == .rectangle ? .rectangle : .pixelate)
            let start = clampedToImage(p)
            let a = Annotation(kind: kind, start: start, end: start, color: session.color, strokeWidth: session.strokeWidthPx)
            document.beginGesture()
            document.updateLive { $0.annotations.append(a) }
            session.select(a.id)
            interaction = .creating(a.id)

        case .text:
            if let hit = annotationHit(at: p), hit.kind == .text {
                session.select(hit.id)
                beginTextEditing(existing: hit)
            } else {
                beginTextEditing(existing: nil, at: clampedToImage(p))
            }

        case .crop:
            if let crop = document.state.cropRect,
               let handle = Handle.corners.first(where: {
                   let hp = $0.position(in: crop)
                   return hypot(hp.x - p.x, hp.y - p.y) <= handleTolerance
               }) {
                document.beginGesture()
                interaction = .cropResize(handle)
            } else {
                document.beginGesture()
                interaction = .cropNew(origin: clampedToImage(p))
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let current = interaction else { return }
        let raw = pixelPoint(event)
        let p = clampedToImage(raw)

        switch current {
        case .creating(let id):
            mutateLive(id) { $0.end = p }
        case .moving(let id, let last):
            let delta = CGSize(width: raw.x - last.x, height: raw.y - last.y)
            mutateLive(id) { $0.translate(by: delta) }
            interaction = .moving(id, last: raw)
        case .resizing(let id, let handle):
            mutateLive(id) { $0.moveHandle(handle, to: p) }
        case .cropNew(let origin):
            document.updateLive { $0.cropRect = CGRect(from: origin, to: p) }
        case .cropResize(let handle):
            document.updateLive { state in
                if let r = state.cropRect { state.cropRect = RectHandles.resized(r, handle: handle, to: p) }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let finished = interaction else { return }
        interaction = nil

        switch finished {
        case .creating(let id):
            if let a = document.annotation(id: id), isDegenerate(a) {
                document.cancelGesture()
                session.select(nil)
            } else {
                document.endGesture()
            }
        case .cropNew:
            if let r = document.state.cropRect, r.width < 4 || r.height < 4 {
                document.cancelGesture()
            } else {
                snapCropToPixels()
                document.endGesture()
            }
        case .cropResize:
            snapCropToPixels()
            document.endGesture()
        case .moving, .resizing:
            document.endGesture()
        }
        needsDisplay = true
    }

    private func snapCropToPixels() {
        document.updateLive { state in
            if let r = state.cropRect { state.cropRect = r.integral }
        }
    }

    private func isDegenerate(_ a: Annotation) -> Bool {
        switch a.kind {
        case .arrow: return hypot(a.end.x - a.start.x, a.end.y - a.start.y) < 6
        case .rectangle, .pixelate: return a.bounds.width < 4 || a.bounds.height < 4
        case .text: return a.text.isEmpty
        }
    }

    private func mutateLive(_ id: UUID, _ change: (inout Annotation) -> Void) {
        document.updateLive { state in
            guard let i = state.annotations.firstIndex(where: { $0.id == id }) else { return }
            change(&state.annotations[i])
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers?.lowercased(),
           let tool = EditorTool.allCases.first(where: { $0.key == chars }) {
            session.setTool(tool)
            return
        }
        switch event.keyCode {
        case 51, 117: session.deleteSelection() // ⌫ / ⌦
        case 53: session.requestClose?()        // Esc
        default: super.keyDown(with: event)
        }
    }

    // MARK: In-place text editing

    func beginTextEditing(existing: Annotation?, at point: CGPoint = .zero) {
        endTextEditing()

        let annotation = existing ?? Annotation(
            kind: .text, start: point, end: point, color: session.color, strokeWidth: 0,
            text: "", fontSize: session.fontSizePx, textBackground: session.textBackground)
        editing = annotation
        editingIsNew = existing == nil

        let pad = TextLayout.padding(fontSize: annotation.fontSize) / scale
        let tv = AnnotationTextView(frame: NSRect(
            x: annotation.start.x / scale, y: annotation.start.y / scale, width: 80, height: 30))
        tv.delegate = self
        tv.onCancel = { [weak self] in self?.endTextEditing() }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = TextLayout.font(size: annotation.fontSize / scale)
        tv.textColor = annotation.textColor.nsColor
        tv.insertionPointColor = annotation.textColor.nsColor
        tv.drawsBackground = annotation.textBackground
        tv.backgroundColor = annotation.color.nsColor
        tv.textContainerInset = NSSize(width: pad, height: pad)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.string = annotation.text
        tv.setAccessibilityLabel("Annotation text")
        addSubview(tv)
        textView = tv
        fitTextView()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) { fitTextView() }

    func textDidEndEditing(_ notification: Notification) { endTextEditing() }

    private func fitTextView() {
        guard let tv = textView, let lm = tv.layoutManager, let container = tv.textContainer else { return }
        lm.ensureLayout(for: container)
        let used = lm.usedRect(for: container)
        let inset = tv.textContainerInset
        tv.setFrameSize(NSSize(
            width: max(used.width + 2 * inset.width + 6, 40 + 2 * inset.width),
            height: max(used.height, tv.font?.boundingRectForFont.height ?? 20) + 2 * inset.height))
    }

    /// Commits (or discards, if empty) the text being edited. Safe to call repeatedly.
    func endTextEditing() {
        guard let tv = textView, var annotation = editing else { return }
        textView = nil
        editing = nil
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        tv.delegate = nil
        tv.removeFromSuperview()
        window?.makeFirstResponder(self)

        annotation.text = text
        if editingIsNew {
            if !text.isEmpty {
                document.mutate { $0.annotations.append(annotation) }
                session.select(annotation.id)
            }
        } else if text.isEmpty {
            document.mutate { $0.annotations.removeAll { $0.id == annotation.id } }
        } else {
            document.mutate { state in
                if let i = state.annotations.firstIndex(where: { $0.id == annotation.id }) {
                    state.annotations[i].text = text
                }
            }
        }
        needsDisplay = true
    }
}
