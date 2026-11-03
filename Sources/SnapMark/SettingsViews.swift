import AppKit
import SnapMarkCore
import SwiftUI

/// Source of truth for the shortcut table; persists on every change and re-registers hotkeys.
@MainActor
final class ShortcutsModel: ObservableObject {
    @Published var configs: [ShortcutConfig] {
        didSet {
            store.save(configs)
            HotkeyManager.shared.register(configs)
            failedIDs = HotkeyManager.shared.failedIDs
        }
    }
    @Published private(set) var failedIDs: Set<UUID> = []

    private let store: ShortcutStore

    init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
        configs = store.load() ?? ShortcutConfig.defaults
        if store.load() == nil { store.save(configs) }
    }

    func start() {
        HotkeyManager.shared.register(configs)
        failedIDs = HotkeyManager.shared.failedIDs
    }

    func add() {
        configs.append(ShortcutConfig(mode: .region, action: .copy))
    }

    func remove(_ id: UUID) {
        configs.removeAll { $0.id == id }
    }
}

struct SettingsView: View {
    @ObservedObject var shortcuts: ShortcutsModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            ShortcutsTab(model: shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 420)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: ShortcutsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each shortcut pairs a capture mode with what happens afterwards.")
                .foregroundStyle(.secondary)

            List {
                ForEach($model.configs) { $config in
                    ShortcutRow(config: $config, failed: model.failedIDs.contains(config.id)) {
                        model.remove(config.id)
                    }
                }
            }
            .frame(minHeight: 200)
            .accessibilityLabel("Shortcuts table")

            HStack {
                Button { model.add() } label: { Label("Add Shortcut", systemImage: "plus") }
                Spacer()
                Button("Keyboard Settings…") { PermissionChecker.openKeyboardShortcutsSettings() }
            }

            Label {
                Text("To use ⌘⇧3 / ⌘⇧4 / ⌘⇧5, first turn off the built-in macOS screenshot shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots. Until then macOS handles those keys itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

private struct ShortcutRow: View {
    @Binding var config: ShortcutConfig
    let failed: Bool
    let onDelete: () -> Void

    private var warning: String? {
        if failed { return "This combination is already in use by another app or macOS." }
        return config.keyCombo.flatMap(SystemShortcuts.conflict(for:))
    }

    var body: some View {
        HStack(spacing: 10) {
            ShortcutRecorder(combo: $config.keyCombo)
                .frame(width: 130, height: 24)

            Picker("Capture mode", selection: $config.mode) {
                ForEach(CaptureMode.available) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("After capture", selection: $config.action) {
                ForEach(AfterCaptureAction.available) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(width: 160)

            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(warning)
                    .accessibilityLabel("Shortcut conflict")
                    .accessibilityHint(warning)
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
        }
        .padding(.vertical, 2)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    private var preview: String {
        FileNamer.baseName(template: settings.fileNameTemplate, date: Date()) + ".png"
    }

    var body: some View {
        Form {
            Section("Saving") {
                HStack {
                    Text(settings.saveFolderDescription).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { settings.chooseSaveFolder() }
                    Button("Reset") { settings.resetSaveFolder() }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Save folder")

                TextField("File name", text: $settings.fileNameTemplate)
                    .accessibilityLabel("File name template")
                Text("Preview: \(preview)").font(.callout).foregroundStyle(.secondary)
                Text("Wrap date patterns in braces, e.g. {yyyy-MM-dd} and {HH.mm.ss}.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                HStack {
                    Image(systemName: PermissionChecker.isScreenRecordingGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(PermissionChecker.isScreenRecordingGranted ? .green : .red)
                    Text(PermissionChecker.isScreenRecordingGranted ? "Screen Recording allowed" : "Screen Recording not allowed")
                    Spacer()
                    Button("Open System Settings") { PermissionChecker.openScreenRecordingSettings() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Onboarding

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var granted = PermissionChecker.isScreenRecordingGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to SnapMark").font(.largeTitle.bold())
            Text("SnapMark runs entirely on your Mac. It never uses the network.")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: granted ? "checkmark.circle.fill" : "1.circle.fill")
                            .foregroundStyle(granted ? .green : .accentColor)
                        Text("Allow Screen Recording").font(.headline)
                    }
                    Text("macOS requires this before any app can capture the screen. Click the button, switch SnapMark on in Privacy & Security → Screen Recording, then restart SnapMark if macOS asks.")
                        .fixedSize(horizontal: false, vertical: true)
                    if granted {
                        Label("Access granted", systemImage: "checkmark").foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("Allow Screen Recording") {
                                PermissionChecker.requestScreenRecording()
                                PermissionChecker.openScreenRecordingSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Restart SnapMark") { PermissionChecker.relaunch() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "2.circle.fill").foregroundStyle(Color.accentColor)
                        Text("Free up ⌘⇧3 / ⌘⇧4 / ⌘⇧5 (optional)").font(.headline)
                    }
                    Text("SnapMark's default shortcuts are ⌘⇧2 (region → clipboard) and ⌘⇧3 (region → editor). macOS owns ⌘⇧3 by default, so turn off its screenshot shortcuts under Keyboard Shortcuts → Screenshots if you want to use them. You can remap everything in Settings.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard Settings") { PermissionChecker.openKeyboardShortcutsSettings() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Get Started", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(timer) { _ in granted = PermissionChecker.isScreenRecordingGranted }
    }
}
