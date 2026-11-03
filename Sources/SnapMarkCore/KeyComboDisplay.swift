import Foundation

public extension KeyCombo {
    /// "⌘⇧2"-style label, modifiers in the standard macOS order (⌃⌥⇧⌘).
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// A global hotkey needs at least one of ⌘ ⌃ ⌥ so it can't hijack ordinary typing.
    var isValidGlobalHotkey: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// Known system-owned shortcuts that silently win over an app's global hotkey.
/// (Phase 4 adds a live read of the user's actual symbolic-hotkey settings.)
public enum SystemShortcuts {
    public static func conflict(for combo: KeyCombo) -> String? {
        let screenshotKeys: [Int: String] = [20: "⌘⇧3", 21: "⌘⇧4", 23: "⌘⇧5", 22: "⌘⇧6"]
        if combo.modifiers == [.command, .shift], let name = screenshotKeys[combo.keyCode] {
            return "\(name) is a built-in macOS screenshot shortcut. It only works here after you turn it off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots."
        }
        if combo.modifiers == [.command], combo.keyCode == 49 {
            return "⌘Space is used by Spotlight."
        }
        if combo.modifiers == [.command], combo.keyCode == 48 {
            return "⌘⇥ is the macOS app switcher."
        }
        return nil
    }
}
