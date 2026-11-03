import Foundation

public enum CaptureMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case region, window, fullScreen, repeatLast, timed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .region: "Region"
        case .window: "Window"
        case .fullScreen: "Full Screen"
        case .repeatLast: "Repeat Last Region"
        case .timed: "Timed"
        }
    }

    /// Modes the current build can execute. Later phases extend this list.
    public static let available: [CaptureMode] = [.region]
}

public enum AfterCaptureAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case copy, editor, save, copyAndSave, thumbnail

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .copy: "Copy to Clipboard"
        case .editor: "Open Editor"
        case .save: "Save to Folder"
        case .copyAndSave: "Copy + Save"
        case .thumbnail: "Floating Thumbnail"
        }
    }

    /// Actions the current build can execute. Later phases extend this list.
    public static let available: [AfterCaptureAction] = [.copy, .editor, .save, .copyAndSave]
}

/// A global hotkey: virtual key code (kVK_*) plus modifiers. Platform-neutral so it stays Codable and testable.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// One user-defined shortcut row: (capture mode, after-capture action) bound to a key combination.
public struct ShortcutConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var mode: CaptureMode
    public var action: AfterCaptureAction
    /// Seconds, only used by `.timed`.
    public var timedDelay: Int
    public var keyCombo: KeyCombo?

    public init(
        id: UUID = UUID(), mode: CaptureMode, action: AfterCaptureAction,
        timedDelay: Int = 3, keyCombo: KeyCombo? = nil
    ) {
        self.id = id
        self.keyCombo = keyCombo
        self.mode = mode
        self.action = action
        self.timedDelay = timedDelay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mode = try c.decode(CaptureMode.self, forKey: .mode)
        action = try c.decode(AfterCaptureAction.self, forKey: .action)
        timedDelay = try c.decodeIfPresent(Int.self, forKey: .timedDelay) ?? 3
        keyCombo = try c.decodeIfPresent(KeyCombo.self, forKey: .keyCombo)
    }

    public var summary: String { "\(mode.displayName) → \(action.displayName)" }

    public static let defaultRegionCopyID = UUID(uuidString: "6F1C2B54-0000-4000-8000-000000000002")!
    public static let defaultRegionEditorID = UUID(uuidString: "6F1C2B54-0000-4000-8000-000000000003")!

    public static var defaults: [ShortcutConfig] {
        [
            // kVK_ANSI_2 = 19, kVK_ANSI_3 = 20
            ShortcutConfig(id: defaultRegionCopyID, mode: .region, action: .copy,
                           keyCombo: KeyCombo(keyCode: 19, modifiers: [.command, .shift])),
            ShortcutConfig(id: defaultRegionEditorID, mode: .region, action: .editor,
                           keyCombo: KeyCombo(keyCode: 20, modifiers: [.command, .shift])),
        ]
    }
}

/// Persists the shortcut list as JSON in UserDefaults.
public struct ShortcutStore {
    public static let key = "snapmark.shortcuts.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` when nothing valid has been saved yet (first launch or corrupt data).
    public func load() -> [ShortcutConfig]? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode([ShortcutConfig].self, from: data)
    }

    public func save(_ configs: [ShortcutConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
