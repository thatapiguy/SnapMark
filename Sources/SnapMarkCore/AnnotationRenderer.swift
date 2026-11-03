import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws annotations. Contract: the context's CTM is top-left origin, y down, 1 unit = 1 image pixel.
/// The live canvas and the exporter both call `draw`, so what you see is what gets exported.
public enum AnnotationRenderer {
    public static func draw(
        _ annotations: [Annotation],
        in ctx: CGContext,
        base: CGImage,
        scale: CGFloat,
        skipping skipID: UUID? = nil
    ) {
        for a in annotations where a.id != skipID {
            ctx.saveGState()
            defer { ctx.restoreGState() }
            switch a.kind {
            case .rectangle: drawRectangle(a, in: ctx)
            case .arrow: drawArrow(a, in: ctx, scale: scale)
            case .text: drawText(a, in: ctx)
            case .pixelate: drawPixelate(a, in: ctx, base: base, scale: scale)
            }
        }
    }

    /// Flattens base + annotations at the base image's native resolution, then applies the crop.
    public static func render(
        base: CGImage,
        annotations: [Annotation],
        cropRect: CGRect?
    ) -> CGImage? {
        let width = base.width, height = base.height
        let space: CGColorSpace = {
            if let cs = base.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: info
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Switch to top-left, y-down for annotation drawing.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(annotations, in: ctx, base: base, scale: 1)

        guard let flattened = ctx.makeImage() else { return nil }
        guard let crop = cropRect else { return flattened }
        let clipped = crop.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard clipped.width >= 1, clipped.height >= 1 else { return flattened }
        return flattened.cropping(to: clipped)
    }

    // MARK: Shapes

    private static func drawRectangle(_ a: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.strokeWidth)
        ctx.setLineJoin(.round)
        ctx.stroke(a.bounds)
    }

    private static func drawArrow(_ a: Annotation, in ctx: CGContext, scale: CGFloat) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let length = hypot(dx, dy)
        guard length >= 1 else { return }
        let ux = dx / length, uy = dy / length

        let headLength = min(max(a.strokeWidth * 4.5, 10 * scale), length * 0.8)
        let halfAngle: CGFloat = 0.45
        func rotated(_ angle: CGFloat) -> CGPoint {
            // Vector pointing back from the tip, rotated by `angle`.
            let bx = -ux, by = -uy
            return CGPoint(
                x: a.end.x + headLength * (bx * cos(angle) - by * sin(angle)),
                y: a.end.y + headLength * (bx * sin(angle) + by * cos(angle))
            )
        }
        let left = rotated(halfAngle), right = rotated(-halfAngle)

        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.strokeWidth)
        ctx.setLineCap(.round)

        // Stop the shaft inside the head so a thick line doesn't poke past the tip.
        let shaftEnd = CGPoint(x: a.end.x - ux * headLength * 0.7, y: a.end.y - uy * headLength * 0.7)
        ctx.move(to: a.start)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.move(to: a.end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ a: Annotation, in ctx: CGContext) {
        guard !a.text.isEmpty else { return }
        let pad = TextLayout.padding(fontSize: a.fontSize)
        let box = a.bounds

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        if a.textBackground {
            a.color.nsColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: pad * 0.8, yRadius: pad * 0.8).fill()
        }
        (a.text as NSString).draw(
            at: CGPoint(x: box.minX + pad, y: box.minY + pad),
            withAttributes: [.font: TextLayout.font(size: a.fontSize), .foregroundColor: a.textColor.nsColor]
        )
    }

    /// Irreversible pixelation: the region is averaged down and redrawn blocky, so the original
    /// detail is not present in anything that gets exported or copied.
    private static func drawPixelate(_ a: Annotation, in ctx: CGContext, base: CGImage, scale: CGFloat) {
        let region = a.bounds.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard region.width >= 1, region.height >= 1, let sub = base.cropping(to: region) else { return }

        let block = max(4, 8 * scale)
        let smallW = max(1, Int((region.width / block).rounded(.up)))
        let smallH = max(1, Int((region.height / block).rounded(.up)))
        guard let small = CGContext(
            data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        small.interpolationQuality = .high
        small.draw(sub, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let reduced = small.makeImage() else { return }

        ctx.clip(to: region)
        ctx.interpolationQuality = .none
        drawImage(reduced, in: region, ctx: ctx)
    }

    /// Draws an upright image into `rect` of a top-left-origin context.
    static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}

public enum ImageEncoder {
    /// PNG with DPI metadata so a 2x capture reports its point size correctly in other apps.
    public static func pngData(_ image: CGImage, pixelScale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * pixelScale
        let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
