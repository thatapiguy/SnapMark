import AppKit
import CoreGraphics

public struct RGBAColor: Codable, Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    public static let red = RGBAColor(r: 0.93, g: 0.20, b: 0.20)
    public static let orange = RGBAColor(r: 0.98, g: 0.55, b: 0.10)
    public static let yellow = RGBAColor(r: 1.00, g: 0.80, b: 0.10)
    public static let green = RGBAColor(r: 0.20, g: 0.72, b: 0.35)
    public static let blue = RGBAColor(r: 0.15, g: 0.45, b: 0.95)
    public static let black = RGBAColor(r: 0.08, g: 0.08, b: 0.08)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)

    public static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .black]
}

public enum AnnotationKind: String, Codable, Sendable {
    case arrow, rectangle, text, pixelate
}

/// One editable object. All coordinates are in image pixels, origin top-left.
/// Two-point shapes use `start`/`end` (not necessarily normalized); text uses `start` as its top-left.
public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    public var start: CGPoint
    public var end: CGPoint
    public var color: RGBAColor
    /// Pixels.
    public var strokeWidth: CGFloat
    public var text: String
    /// Pixels.
    public var fontSize: CGFloat
    public var textBackground: Bool

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        start: CGPoint,
        end: CGPoint,
        color: RGBAColor = .red,
        strokeWidth: CGFloat = 4,
        text: String = "",
        fontSize: CGFloat = 32,
        textBackground: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.text = text
        self.fontSize = fontSize
        self.textBackground = textBackground
    }

    public var bounds: CGRect {
        switch kind {
        case .arrow, .rectangle, .pixelate:
            return CGRect(from: start, to: end)
        case .text:
            return CGRect(origin: start, size: TextLayout.boxSize(text: text, fontSize: fontSize))
        }
    }

    /// Text color: the annotation color, or a contrasting one when drawn on a filled background.
    public var textColor: RGBAColor {
        guard textBackground else { return color }
        return color.luminance > 0.6 ? .black : .white
    }

    // MARK: Hit testing & handles

    public func hitTest(_ p: CGPoint, tolerance t: CGFloat) -> Bool {
        switch kind {
        case .arrow:
            return Self.distance(from: p, toSegment: start, end) <= t + strokeWidth / 2
        case .rectangle:
            let outer = bounds.insetBy(dx: -(t + strokeWidth / 2), dy: -(t + strokeWidth / 2))
            let inner = bounds.insetBy(dx: t + strokeWidth / 2, dy: t + strokeWidth / 2)
            if inner.width <= 0 || inner.height <= 0 { return outer.contains(p) }
            return outer.contains(p) && !inner.contains(p)
        case .pixelate, .text:
            return bounds.insetBy(dx: -t, dy: -t).contains(p)
        }
    }

    public var handles: [(Handle, CGPoint)] {
        switch kind {
        case .arrow:
            return [(.start, start), (.end, end)]
        case .rectangle, .pixelate:
            let b = bounds
            return Handle.corners.map { ($0, $0.position(in: b)) }
        case .text:
            return []
        }
    }

    public mutating func moveHandle(_ handle: Handle, to p: CGPoint) {
        switch handle {
        case .start: start = p
        case .end: end = p
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let fixed = handle.opposite(in: bounds)
            start = fixed
            end = p
        }
    }

    public mutating func translate(by d: CGSize) {
        start.x += d.width; start.y += d.height
        end.x += d.width; end.y += d.height
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Shared by the renderer (final pixels) and the live text editor so both agree on geometry.
public enum TextLayout {
    public static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    public static func padding(fontSize: CGFloat) -> CGFloat { fontSize * 0.3 }

    public static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let measured = (text.isEmpty ? " " : text) as NSString
        let size = measured.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font(size: fontSize)]
        ).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    public static func boxSize(text: String, fontSize: CGFloat) -> CGSize {
        let s = textSize(text, fontSize: fontSize)
        let pad = padding(fontSize: fontSize)
        return CGSize(width: s.width + 2 * pad, height: s.height + 2 * pad)
    }
}
