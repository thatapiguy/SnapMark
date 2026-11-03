import Foundation
import Testing
@testable import SnapMarkCore

@Suite struct ShortcutConfigTests {
    private func freshDefaults() -> UserDefaults {
        let name = "snapmark.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func loadReturnsNilWhenNothingSaved() {
        #expect(ShortcutStore(defaults: freshDefaults()).load() == nil)
    }

    @Test func roundTripPreservesOrderAndFields() {
        let store = ShortcutStore(defaults: freshDefaults())
        let configs = [
            ShortcutConfig(mode: .region, action: .copyAndSave,
                           keyCombo: KeyCombo(keyCode: 21, modifiers: [.command, .option])),
            ShortcutConfig(mode: .timed, action: .editor, timedDelay: 10),
        ]
        store.save(configs)
        #expect(store.load() == configs)
    }

    @Test func corruptDataLoadsAsNil() {
        let d = freshDefaults()
        d.set(Data("not json".utf8), forKey: ShortcutStore.key)
        #expect(ShortcutStore(defaults: d).load() == nil)
    }

    @Test func decodesOlderRecordsWithoutTimedDelay() throws {
        let json = #"[{"id":"6F1C2B54-0000-4000-8000-000000000002","mode":"region","action":"copy"}]"#
        let decoded = try JSONDecoder().decode([ShortcutConfig].self, from: Data(json.utf8))
        #expect(decoded.first?.timedDelay == 3)
    }

    @Test func defaultsShipWithDistinctKeyCombos() {
        let combos = ShortcutConfig.defaults.compactMap(\.keyCombo)
        #expect(combos.count == 2 && Set(combos).count == 2)
    }

    @Test func defaultsHaveStableDistinctIDs() {
        let ids = ShortcutConfig.defaults.map(\.id)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids == ShortcutConfig.defaults.map(\.id))
    }
}

@Suite struct FileNamerTests {
    private let utc = TimeZone(identifier: "UTC")!
    private var date: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 5; c.hour = 14; c.minute = 7; c.second = 9
        c.timeZone = utc
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test func expandsDefaultTemplate() {
        let name = FileNamer.baseName(template: FileNamer.defaultTemplate, date: date, timeZone: utc)
        #expect(name == "Screenshot 2026-03-05 at 14.07.09")
    }

    @Test func replacesPathUnsafeCharacters() {
        let name = FileNamer.baseName(template: "a/b {HH:mm}", date: date, timeZone: utc)
        #expect(name == "a-b 14-07")
    }

    @Test func unbalancedBraceStaysLiteral() {
        #expect(FileNamer.baseName(template: "shot {oops", date: date, timeZone: utc) == "shot {oops")
    }

    @Test func emptyTemplateFallsBack() {
        #expect(FileNamer.baseName(template: "  ", date: date, timeZone: utc) == "Screenshot")
    }

    @Test func uniqueURLAppendsCounter() {
        let dir = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/shot.png", "/tmp/x/shot 2.png"]
        let url = FileNamer.uniqueURL(directory: dir, baseName: "shot", ext: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "shot 3.png")
    }
}

@Suite struct CoordinateMapperTests {
    @Test func retinaScaleDoublesCoordinates() {
        let r = CoordinateMapper.pixelRect(
            forSelection: CGRect(x: 10, y: 20, width: 100, height: 50),
            viewSize: CGSize(width: 1000, height: 500),
            imageSize: CGSize(width: 2000, height: 1000))
        #expect(r == CGRect(x: 20, y: 40, width: 200, height: 100))
    }

    @Test func fractionalScaleRoundsEdges() {
        let r = CoordinateMapper.pixelRect(
            forSelection: CGRect(x: 1, y: 1, width: 3, height: 3),
            viewSize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 150, height: 150))
        #expect(r == CGRect(x: 2, y: 2, width: 4, height: 4)) // edges 1.5→2 and 6.0→6
    }

    @Test func clampsToImage() {
        let r = CoordinateMapper.pixelRect(
            forSelection: CGRect(x: 90, y: 90, width: 50, height: 50),
            viewSize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 100, height: 100))
        #expect(r == CGRect(x: 90, y: 90, width: 10, height: 10))
    }
}

@Suite struct KeyComboTests {
    @Test func displayStringUsesStandardModifierOrder() {
        let c = KeyCombo(keyCode: 19, modifiers: [.command, .shift, .option, .control])
        #expect(c.displayString == "⌃⌥⇧⌘2")
    }

    @Test func shiftAloneIsNotAValidGlobalHotkey() {
        #expect(!KeyCombo(keyCode: 19, modifiers: [.shift]).isValidGlobalHotkey)
        #expect(KeyCombo(keyCode: 19, modifiers: [.command]).isValidGlobalHotkey)
    }

    @Test func flagsNativeScreenshotShortcuts() {
        #expect(SystemShortcuts.conflict(for: KeyCombo(keyCode: 21, modifiers: [.command, .shift])) != nil)
        #expect(SystemShortcuts.conflict(for: KeyCombo(keyCode: 19, modifiers: [.command, .shift])) == nil)
    }
}
