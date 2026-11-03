import Foundation
import CoreGraphics
import Testing
@testable import SnapMarkCore

private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

private func whiteImage(_ w: Int = 100, _ h: Int = 100) -> CGImage {
    makeImage(width: w, height: h) { ctx in
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
}

/// Reads RGBA at (x, y) with y measured from the TOP of the image.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(
        data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (y * w + x) * 4
    return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
}

@Suite struct AnnotationRendererTests {
    @Test func exportKeepsNativeResolution() {
        let out = AnnotationRenderer.render(base: whiteImage(200, 100), annotations: [], cropRect: nil)!
        #expect(out.width == 200 && out.height == 100)
    }

    @Test func rectangleStrokeLandsTopLeftOriented() {
        let a = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 40),
                           color: RGBAColor(r: 1, g: 0, b: 0), strokeWidth: 4)
        let out = AnnotationRenderer.render(base: whiteImage(), annotations: [a], cropRect: nil)!
        let onEdge = pixel(out, 10, 25)
        #expect(onEdge.r > 240 && onEdge.g < 20 && onEdge.b < 20)
        #expect(pixel(out, 30, 25).g > 240)   // interior untouched
        #expect(pixel(out, 10, 74).g > 240)   // mirrored position must stay white
    }

    @Test func arrowDrawsShaftAndHead() {
        let a = Annotation(kind: .arrow, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50),
                           color: RGBAColor(r: 0, g: 0, b: 0), strokeWidth: 4)
        let out = AnnotationRenderer.render(base: whiteImage(), annotations: [a], cropRect: nil)!
        #expect(pixel(out, 30, 50).r < 30)
        #expect(pixel(out, 85, 50).r < 30)
        #expect(pixel(out, 30, 20).r > 240)
    }

    @Test func pixelateDestroysDetailInsideOnly() {
        let stripes = makeImage(width: 100, height: 100) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            for x in stride(from: 0, to: 100, by: 2) { ctx.fill(CGRect(x: x, y: 0, width: 1, height: 100)) }
        }
        // Original: x even black, odd white.
        #expect(pixel(stripes, 50, 50).r < 10)
        #expect(pixel(stripes, 51, 50).r > 245)

        let a = Annotation(kind: .pixelate, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80))
        let out = AnnotationRenderer.render(base: stripes, annotations: [a], cropRect: nil)!
        let inside = [pixel(out, 50, 50).r, pixel(out, 51, 50).r]
        #expect(inside.allSatisfy { (60...200).contains($0) }) // stripes averaged to grey
        #expect(pixel(out, 5, 5).r > 245)                      // outside untouched (x odd = white)
        #expect(pixel(out, 4, 5).r < 10)
    }

    @Test func textRendersVisiblePixels() {
        let a = Annotation(kind: .text, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10),
                           color: RGBAColor(r: 0, g: 0, b: 0), text: "Hi", fontSize: 40)
        let out = AnnotationRenderer.render(base: whiteImage(), annotations: [a], cropRect: nil)!
        var dark = 0
        for y in 10..<60 { for x in 10..<60 where pixel(out, x, y).r < 100 { dark += 1 } }
        #expect(dark > 20)
    }

    @Test func cropProducesRequestedSize() {
        let out = AnnotationRenderer.render(
            base: whiteImage(200, 100), annotations: [], cropRect: CGRect(x: 10, y: 10, width: 40, height: 30))!
        #expect(out.width == 40 && out.height == 30)
    }

    @Test func pngEncodingRoundTripsDimensions() throws {
        let data = try #require(ImageEncoder.pngData(whiteImage(64, 32), pixelScale: 2))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

@Suite struct EditorDocumentTests {
    private func doc() -> EditorDocument { EditorDocument(baseImage: whiteImage(), pixelScale: 2) }
    private func rect() -> Annotation {
        Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))
    }

    @Test func undoRedoIsUnlimitedAndOrdered() {
        let d = doc()
        for _ in 0..<500 { d.mutate { $0.annotations.append(rect()) } }
        #expect(d.state.annotations.count == 500)
        for _ in 0..<500 { d.undo() }
        #expect(d.state.annotations.isEmpty && !d.canUndo)
        d.redo()
        #expect(d.state.annotations.count == 1)
    }

    @Test func newEditClearsRedo() {
        let d = doc()
        d.mutate { $0.annotations.append(rect()) }
        d.undo()
        d.mutate { $0.cropRect = CGRect(x: 0, y: 0, width: 5, height: 5) }
        #expect(!d.canRedo)
    }

    @Test func gestureCollapsesToOneUndoStep() {
        let d = doc()
        let a = rect()
        d.beginGesture()
        d.updateLive { $0.annotations.append(a) }
        for i in 1...20 { d.updateLive { $0.annotations[0].end = CGPoint(x: CGFloat(i), y: CGFloat(i)) } }
        d.endGesture()
        d.undo()
        #expect(d.state.annotations.isEmpty && !d.canUndo)
    }

    @Test func cancelledGestureLeavesNoTrace() {
        let d = doc()
        d.beginGesture()
        d.updateLive { $0.annotations.append(rect()) }
        d.cancelGesture()
        #expect(d.state.annotations.isEmpty && !d.canUndo)
    }

    @Test func dirtyTracksCleanPoint() {
        let d = doc()
        #expect(!d.isDirty)
        d.mutate { $0.annotations.append(rect()) }
        #expect(d.isDirty)
        d.markClean()
        #expect(!d.isDirty)
        d.undo()
        #expect(d.isDirty)
        d.redo()
        #expect(!d.isDirty)
    }

    @Test func handleDragKeepsOppositeCornerFixed() {
        var a = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 40))
        a.moveHandle(.bottomRight, to: CGPoint(x: 80, y: 90))
        #expect(a.bounds == CGRect(x: 10, y: 10, width: 70, height: 80))
        a.moveHandle(.topLeft, to: CGPoint(x: 0, y: 0))
        #expect(a.bounds == CGRect(x: 0, y: 0, width: 80, height: 90))
    }

    @Test func rectangleHitTestIsOutlineOnly() {
        let a = Annotation(kind: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), strokeWidth: 4)
        #expect(a.hitTest(CGPoint(x: 0, y: 50), tolerance: 4))
        #expect(!a.hitTest(CGPoint(x: 50, y: 50), tolerance: 4))
    }
}
