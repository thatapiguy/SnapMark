import AppKit
import SnapMarkCore
import SwiftUI

struct EditorRootView: View {
    @ObservedObject var session: EditorSession
    var onCopyAndClose: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(session: session, onCopyAndClose: onCopyAndClose, onSave: onSave)
            Divider()
            CanvasScrollView(session: session)
        }
    }
}

struct EditorToolbar: View {
    @ObservedObject var session: EditorSession
    var onCopyAndClose: () -> Void
    var onSave: () -> Void

    private var showsTextOptions: Bool {
        session.tool == .text
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases) { tool in
                    Button { session.setTool(tool) } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 28, height: 24)
                            .background(session.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title) (\(tool.key.uppercased()))")
                    .accessibilityLabel(tool.title)
                    .accessibilityHint("Shortcut \(tool.key.uppercased())")
                    .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 5) {
                ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { _, color in
                    Button { session.setColor(color) } label: {
                        Circle()
                            .fill(Color(nsColor: color.nsColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(session.color == color ? 0.9 : 0.2),
                                                           lineWidth: session.color == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(colorName(color))")
                    .accessibilityAddTraits(session.color == color ? .isSelected : [])
                }
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Custom color")
            }

            HStack(spacing: 3) {
                ForEach(0..<EditorSession.widthPoints.count, id: \.self) { i in
                    Button { session.setWidthIndex(i) } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary)
                            .frame(width: 16, height: EditorSession.widthPoints[i])
                            .frame(width: 24, height: 22)
                            .background(session.widthIndex == i ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(["Thin", "Medium", "Thick"][i] + " stroke")
                    .accessibilityAddTraits(session.widthIndex == i ? .isSelected : [])
                }
            }

            if showsTextOptions {
                Picker("Font size", selection: Binding(get: { session.fontIndex }, set: { session.setFontIndex($0) })) {
                    Text("S").tag(0); Text("M").tag(1); Text("L").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                .labelsHidden()
                .accessibilityLabel("Font size")
                Toggle("Fill", isOn: Binding(get: { session.textBackground }, set: { session.setTextBackground($0) }))
                    .toggleStyle(.checkbox)
                    .help("Draw text on a filled background")
            }

            Spacer(minLength: 8)

            Button { session.document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo).help("Undo (⌘Z)").accessibilityLabel("Undo")
            Button { session.document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo).help("Redo (⇧⌘Z)").accessibilityLabel("Redo")

            if session.hasCrop {
                Button("Reset Crop") { session.clearCrop() }
            }
            Button("Save", action: onSave).help("Save (⌘S)")
            Button("Copy & Close", action: onCopyAndClose)
                .buttonStyle(.borderedProminent)
                .help("Copy the image and close (⌘↩)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: session.color.nsColor) },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                session.setColor(RGBAColor(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
            })
    }

    private func colorName(_ c: RGBAColor) -> String {
        switch c {
        case .red: "red"
        case .orange: "orange"
        case .yellow: "yellow"
        case .green: "green"
        case .blue: "blue"
        default: "black"
        }
    }
}

struct CanvasScrollView: NSViewRepresentable {
    let session: EditorSession

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor

        let canvas = CanvasView(session: session)
        scrollView.documentView = canvas
        session.canvas = canvas
        DispatchQueue.main.async {
            canvas.fitToWindow()
            canvas.window?.makeFirstResponder(canvas)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
