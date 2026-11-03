import AppKit
import SnapMarkCore
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, text, pixelate, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .text: "Text"
        case .pixelate: "Blur / Pixelate"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .pixelate: "square.grid.3x3.fill"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut.
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .pixelate: "b"
        case .crop: "c"
        }
    }
}

/// State shared between the SwiftUI toolbar and the AppKit canvas.
@MainActor
final class EditorSession: ObservableObject {
    static let widthPoints: [CGFloat] = [2, 4, 7]
    static let fontPoints: [CGFloat] = [14, 20, 30]

    let document: EditorDocument
    private let settings: AppSettings

    @Published var tool: EditorTool = .select
    @Published var color: RGBAColor = .red
    @Published var widthIndex = 1
    @Published var fontIndex = 1
    @Published var textBackground = false
    @Published private(set) var selectedID: UUID?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var hasCrop = false

    weak var canvas: CanvasView?
    var requestClose: (() -> Void)?
    /// Where the last save went, so ⌘S overwrites instead of creating numbered copies.
    var savedURL: URL?

    init(document: EditorDocument, settings: AppSettings) {
        self.document = document
        self.settings = settings
        document.onChange = { [weak self] in self?.documentChanged() }
    }

    var pixelScale: CGFloat { document.pixelScale }
    var strokeWidthPx: CGFloat { Self.widthPoints[widthIndex] * pixelScale }
    var fontSizePx: CGFloat { Self.fontPoints[fontIndex] * pixelScale }

    private func documentChanged() {
        canUndo = document.canUndo
        canRedo = document.canRedo
        hasCrop = document.state.cropRect != nil
        if let id = selectedID, document.annotation(id: id) == nil { selectedID = nil }
        canvas?.documentDidChange()
    }

    // MARK: Tool & selection

    func setTool(_ newTool: EditorTool) {
        canvas?.endTextEditing()
        tool = newTool
        if newTool != .select { selectedID = nil }
        canvas?.toolDidChange()
    }

    func select(_ id: UUID?) {
        selectedID = id
        if let id, let a = document.annotation(id: id) {
            color = a.color
            if a.kind == .text { textBackground = a.textBackground }
        }
        canvas?.documentDidChange()
    }

    // MARK: Style changes apply to the selection as well as future shapes

    func setColor(_ new: RGBAColor) {
        color = new
        modifySelection { $0.color = new }
    }

    func setWidthIndex(_ index: Int) {
        widthIndex = index
        let width = strokeWidthPx
        modifySelection { if $0.kind == .arrow || $0.kind == .rectangle { $0.strokeWidth = width } }
    }

    func setFontIndex(_ index: Int) {
        fontIndex = index
        let size = fontSizePx
        modifySelection { if $0.kind == .text { $0.fontSize = size } }
    }

    func setTextBackground(_ on: Bool) {
        textBackground = on
        modifySelection { if $0.kind == .text { $0.textBackground = on } }
    }

    private func modifySelection(_ change: (inout Annotation) -> Void) {
        guard let id = selectedID else { return }
        document.mutate { state in
            guard let i = state.annotations.firstIndex(where: { $0.id == id }) else { return }
            change(&state.annotations[i])
        }
    }

    func deleteSelection() {
        if tool == .crop, hasCrop {
            document.mutate { $0.cropRect = nil }
        } else if let id = selectedID {
            document.mutate { $0.annotations.removeAll { $0.id == id } }
        }
    }

    func clearCrop() { document.mutate { $0.cropRect = nil } }

    // MARK: Output

    /// Flattened native-resolution image (annotations burned in, crop applied).
    func flattenedImage() -> CGImage? {
        canvas?.endTextEditing()
        return document.renderFlattened()
    }

    func copyToClipboard() -> Bool {
        guard let image = flattenedImage() else { return false }
        ClipboardWriter.write(image, pixelScale: pixelScale)
        document.markClean()
        return true
    }

    /// ⌘S: overwrite the previous save, or write a new file into the configured folder.
    func save() throws {
        guard let image = flattenedImage(), let data = ImageEncoder.pngData(image, pixelScale: pixelScale) else {
            throw SaveError.encodingFailed
        }
        if let url = savedURL {
            try data.write(to: url, options: .atomic)
        } else {
            savedURL = try settings.saveImage(image, pixelScale: pixelScale)
        }
        document.markClean()
    }

    func write(to url: URL) throws {
        guard let image = flattenedImage(), let data = ImageEncoder.pngData(image, pixelScale: pixelScale) else {
            throw SaveError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        savedURL = url
        document.markClean()
    }

    var suggestedFileName: String {
        FileNamer.baseName(template: settings.fileNameTemplate, date: Date()) + ".png"
    }
}
