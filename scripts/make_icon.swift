// Generates Support/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: ~824pt body centered in 1024.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

// Gradient body.
ctx.saveGState()
shape.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.40, green: 0.30, blue: 0.96, alpha: 1),
])!
gradient.draw(in: body, angle: -60)
// Gentle top sheen.
let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
sheen.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

// Viewfinder corner brackets.
let arm: CGFloat = 150
let f = CGRect(x: body.minX + 120, y: body.minY + 120, width: body.width - 240, height: body.height - 240)
let brackets = NSBezierPath()
brackets.lineWidth = 46
brackets.lineCapStyle = .round
brackets.lineJoinStyle = .round
func corner(_ p: CGPoint, _ dx: CGFloat, _ dy: CGFloat) {
    brackets.move(to: CGPoint(x: p.x + dx * arm, y: p.y))
    brackets.line(to: p)
    brackets.line(to: CGPoint(x: p.x, y: p.y + dy * arm))
}
corner(CGPoint(x: f.minX, y: f.minY), 1, 1)
corner(CGPoint(x: f.maxX, y: f.minY), -1, 1)
corner(CGPoint(x: f.minX, y: f.maxY), 1, -1)
corner(CGPoint(x: f.maxX, y: f.maxY), -1, -1)
NSColor.white.setStroke()
brackets.stroke()

// Annotation arrow in the middle.
let coral = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.36, alpha: 1)
let tail = CGPoint(x: 400, y: 400)
let tip = CGPoint(x: 640, y: 640)
let dir = CGPoint(x: (tip.x - tail.x), y: (tip.y - tail.y))
let len = hypot(dir.x, dir.y)
let u = CGPoint(x: dir.x / len, y: dir.y / len)
let headLen: CGFloat = 130
let shaftEnd = CGPoint(x: tip.x - u.x * headLen * 0.7, y: tip.y - u.y * headLen * 0.7)
let shaft = NSBezierPath()
shaft.lineWidth = 56
shaft.lineCapStyle = .round
shaft.move(to: tail)
shaft.line(to: shaftEnd)
coral.setStroke()
shaft.stroke()
func rot(_ a: CGFloat) -> CGPoint {
    let bx = -u.x, by = -u.y
    return CGPoint(x: tip.x + headLen * (bx * cos(a) - by * sin(a)), y: tip.y + headLen * (bx * sin(a) + by * cos(a)))
}
let head = NSBezierPath()
head.move(to: tip)
head.line(to: rot(0.5))
head.line(to: rot(-0.5))
head.close()
coral.setFill()
head.fill()

NSGraphicsContext.restoreGraphicsState()

let outDir = "build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: outDir)
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let master = "build/AppIcon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: master))
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = ["-z", "\(px)", "\(px)", master, "--out", "\(outDir)/icon_\(name).png"]
    p.standardOutput = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit()
}
let icns = Process()
icns.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icns.arguments = ["-c", "icns", outDir, "-o", "Support/AppIcon.icns"]
try! icns.run(); icns.waitUntilExit()
print("Wrote Support/AppIcon.icns")
