import AppKit
import SnapMarkCore

enum ClipboardWriter {
    /// Keeps the lazy TIFF provider alive while the pasteboard may still ask for data.
    private static var provider: LazyTIFFProvider?

    /// PNG is written eagerly (fast, what modern apps read). TIFF is produced only if some
    /// older app actually requests it, so a large Retina capture isn't encoded twice up front.
    static func write(_ image: CGImage, pixelScale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        if let png = ImageEncoder.pngData(image, pixelScale: pixelScale) {
            item.setData(png, forType: .png)
        }
        let lazy = LazyTIFFProvider(image: image, pixelScale: pixelScale)
        provider = lazy
        item.setDataProvider(lazy, forTypes: [.tiff])
        pasteboard.writeObjects([item])
    }
}

private final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let image: CGImage
    let pixelScale: CGFloat

    init(image: CGImage, pixelScale: CGFloat) {
        self.image = image
        self.pixelScale = pixelScale
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff else { return }
        // Point size matters: it's what makes a 2x capture paste at the right size.
        let size = NSSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        if let tiff = NSImage(cgImage: image, size: size).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
    }
}
