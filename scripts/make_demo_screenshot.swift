// Renders docs/images/editor-example.png using SnapMark's own annotation engine, on a made-up
// "dashboard" so no real screen content is shown.
// Run: scripts/make_demo_screenshot.sh
import AppKit
import SnapMarkCore

let W = 1600, H = 1000
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
// Top-left origin, y down.
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}
func text(_ s: String, _ p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let ink = NSColor(white: 0.12, alpha: 1), muted = NSColor(white: 0.45, alpha: 1)

fill(CGRect(x: 0, y: 0, width: W, height: H), NSColor(white: 0.95, alpha: 1))
fill(CGRect(x: 0, y: 0, width: W, height: 64), .white)
text("Acme Analytics", CGPoint(x: 36, y: 18), size: 26, weight: .semibold, color: ink)
fill(CGRect(x: 0, y: 64, width: 260, height: H - 64), NSColor(white: 0.12, alpha: 1))
for (i, item) in ["Overview", "Revenue", "Customers", "Reports", "Settings"].enumerated() {
    if i == 1 { fill(CGRect(x: 16, y: 96 + CGFloat(i) * 64, width: 228, height: 48), NSColor(white: 1, alpha: 0.14), radius: 10) }
    text(item, CGPoint(x: 40, y: 108 + CGFloat(i) * 64), size: 22, weight: .medium, color: .white)
}

// Stat cards.
for (i, (label, value)) in [("Revenue", "$48,210"), ("Orders", "1,284"), ("Visitors", "32.9k")].enumerated() {
    let r = CGRect(x: 300 + CGFloat(i) * 424, y: 100, width: 392, height: 150)
    fill(r, .white, radius: 18)
    text(label, CGPoint(x: r.minX + 28, y: r.minY + 24), size: 22, color: muted)
    text(value, CGPoint(x: r.minX + 28, y: r.minY + 64), size: 52, weight: .bold, color: ink)
}

// Chart.
let chart = CGRect(x: 300, y: 290, width: 1240, height: 330)
fill(chart, .white, radius: 18)
text("Revenue, last 12 weeks", CGPoint(x: chart.minX + 28, y: chart.minY + 22), size: 24, weight: .semibold, color: ink)
let vals: [CGFloat] = [0.35, 0.42, 0.38, 0.5, 0.47, 0.58, 0.55, 0.66, 0.7, 0.68, 0.82, 0.9]
for (i, v) in vals.enumerated() {
    let h = 210 * v
    fill(CGRect(x: chart.minX + 50 + CGFloat(i) * 98, y: chart.maxY - 28 - h, width: 64, height: h),
         NSColor(srgbRed: 0.33, green: 0.52, blue: 0.98, alpha: 1), radius: 8)
}

// Customer table with (fake) emails to redact.
let table = CGRect(x: 300, y: 660, width: 1240, height: 300)
fill(table, .white, radius: 18)
text("Recent customers", CGPoint(x: table.minX + 28, y: table.minY + 22), size: 24, weight: .semibold, color: ink)
let rows = [("Jordan Lee", "jordan.lee@example.com", "$1,240"), ("Sam Rivera", "sam.rivera@example.com", "$860"),
            ("Alex Chen", "alex.chen@example.com", "$2,015"), ("Riley Patel", "riley.patel@example.com", "$430")]
for (i, row) in rows.enumerated() {
    let y = table.minY + 76 + CGFloat(i) * 52
    text(row.0, CGPoint(x: table.minX + 28, y: y), size: 22, weight: .medium, color: ink)
    text(row.1, CGPoint(x: table.minX + 420, y: y), size: 22, color: NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1))
    text(row.2, CGPoint(x: table.maxX - 140, y: y), size: 22, weight: .semibold, color: ink)
}
let base = ctx.makeImage()!

let annotations: [Annotation] = [
    Annotation(kind: .rectangle, start: CGPoint(x: 296, y: 96), end: CGPoint(x: 700, y: 256),
               color: .red, strokeWidth: 8),
    Annotation(kind: .arrow, start: CGPoint(x: 1090, y: 372), end: CGPoint(x: 1380, y: 392),
               color: .red, strokeWidth: 8),
    Annotation(kind: .text, start: CGPoint(x: 800, y: 330), end: CGPoint(x: 800, y: 330),
               color: .red, text: "Up 12% this week!", fontSize: 40, textBackground: true),
    Annotation(kind: .pixelate, start: CGPoint(x: 700, y: 726), end: CGPoint(x: 1170, y: 940),
               color: .red),
]
let out = AnnotationRenderer.render(base: base, annotations: annotations, cropRect: nil)!
let data = ImageEncoder.pngData(out, pixelScale: 2)!
try! data.write(to: URL(fileURLWithPath: "docs/images/editor-example.png"))
print("Wrote docs/images/editor-example.png")
