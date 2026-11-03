import CoreGraphics
import Foundation

/// Editor model: immutable base image + annotations + non-destructive crop, with unlimited undo.
/// Not thread-safe; use from the main thread.
public final class EditorDocument {
    public struct State: Equatable, Sendable {
        public var annotations: [Annotation] = []
        public var cropRect: CGRect?
        public init(annotations: [Annotation] = [], cropRect: CGRect? = nil) {
            self.annotations = annotations
            self.cropRect = cropRect
        }
    }

    public let baseImage: CGImage
    /// Pixels per point of the captured display (2 on Retina).
    public let pixelScale: CGFloat
    public private(set) var state = State()
    public var onChange: (() -> Void)?

    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private var gestureStart: State?
    private var cleanState = State()

    public init(baseImage: CGImage, pixelScale: CGFloat) {
        self.baseImage = baseImage
        self.pixelScale = pixelScale
    }

    public var imageBounds: CGRect { CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height) }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// True when the content differs from the last save/copy.
    public var isDirty: Bool { state != cleanState }

    public func markClean() { cleanState = state }

    public func annotation(id: UUID) -> Annotation? {
        state.annotations.first { $0.id == id }
    }

    /// One undoable step.
    public func mutate(_ change: (inout State) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        undoStack.append(state)
        redoStack.removeAll()
        state = next
        onChange?()
    }

    // MARK: Gestures — many live updates that collapse into a single undo step.

    public func beginGesture() { gestureStart = state }

    public func updateLive(_ change: (inout State) -> Void) {
        change(&state)
        onChange?()
    }

    public func endGesture() {
        defer { gestureStart = nil }
        guard let start = gestureStart, start != state else { return }
        undoStack.append(start)
        redoStack.removeAll()
        onChange?()
    }

    public func cancelGesture() {
        guard let start = gestureStart else { return }
        state = start
        gestureStart = nil
        onChange?()
    }

    // MARK: Undo / redo

    public func undo() {
        guard gestureStart == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        onChange?()
    }

    public func redo() {
        guard gestureStart == nil, let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        onChange?()
    }

    /// Final image at native resolution, with annotations burned in and the crop applied.
    public func renderFlattened() -> CGImage? {
        AnnotationRenderer.render(base: baseImage, annotations: state.annotations, cropRect: state.cropRect)
    }
}
