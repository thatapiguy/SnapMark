import CoreGraphics

public extension CGRect {
    /// Normalized rect spanning two arbitrary corner points.
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Maps a selection made in a display's view (points, top-left origin) to the pixels of the
/// native-resolution capture of that display. Scale is derived from the sizes, so it is right
/// for any backing scale factor (1x, 2x, scaled "looks like" modes).
public enum CoordinateMapper {
    public static func pixelRect(forSelection rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        // Round edges, not size, so adjacent selections tile without gaps.
        let minX = (rect.minX * sx).rounded()
        let minY = (rect.minY * sy).rounded()
        let maxX = (rect.maxX * sx).rounded()
        let maxY = (rect.maxY * sy).rounded()
        let pixels = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return pixels.intersection(CGRect(origin: .zero, size: imageSize))
    }
}

/// Draggable points on an annotation or crop rectangle.
public enum Handle: CaseIterable, Sendable {
    case start, end
    case topLeft, topRight, bottomLeft, bottomRight

    public static let corners: [Handle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    /// Position of a corner handle on `rect` (top-left origin: "top" is minY).
    public func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .start, .end: rect.origin
        }
    }

    /// The corner that stays fixed while this one is dragged.
    public func opposite(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: Handle.bottomRight.position(in: rect)
        case .topRight: Handle.bottomLeft.position(in: rect)
        case .bottomLeft: Handle.topRight.position(in: rect)
        case .bottomRight: Handle.topLeft.position(in: rect)
        case .start, .end: rect.origin
        }
    }
}

public enum RectHandles {
    public static func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        CGRect(from: handle.opposite(in: rect), to: point)
    }
}
