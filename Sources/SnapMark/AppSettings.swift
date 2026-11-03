import AppKit
import Combine
import SnapMarkCore

enum SaveError: LocalizedError {
    case encodingFailed
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "The image could not be encoded."
        case .folderUnavailable: "The save folder is no longer accessible. Choose a folder in Settings."
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let template = "snapmark.fileNameTemplate"
        static let bookmark = "snapmark.saveFolderBookmark"
        static let onboarded = "snapmark.onboardingCompleted"
    }

    @Published var fileNameTemplate: String {
        didSet { defaults.set(fileNameTemplate, forKey: Key.template) }
    }
    @Published private(set) var saveFolderDescription: String = ""

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    private init() {
        fileNameTemplate = defaults.string(forKey: Key.template) ?? FileNamer.defaultTemplate
        saveFolderDescription = describeFolder()
    }

    // MARK: Save folder (sandbox-safe: user-chosen folders persist as security-scoped bookmarks)

    /// The real home directory; inside the sandbox `homeDirectoryForCurrentUser` is the container.
    private static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private var defaultFolder: URL {
        Self.realHome.appendingPathComponent("Pictures/SnapMark", isDirectory: true)
    }

    private func describeFolder() -> String {
        guard let data = defaults.data(forKey: Key.bookmark) else { return "~/Pictures/SnapMark" }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url.path
        }
        return "Unavailable — choose again"
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where SnapMark saves screenshots."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        defaults.set(data, forKey: Key.bookmark)
        saveFolderDescription = url.path
    }

    func resetSaveFolder() {
        defaults.removeObject(forKey: Key.bookmark)
        saveFolderDescription = describeFolder()
    }

    func withSaveFolder<T>(_ body: (URL) throws -> T) throws -> T {
        if let data = defaults.data(forKey: Key.bookmark) {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource()
            else { throw SaveError.folderUnavailable }
            defer { url.stopAccessingSecurityScopedResource() }
            if stale,
               let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Key.bookmark)
            }
            return try body(url)
        }
        try FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        return try body(defaultFolder)
    }

    /// Writes a PNG using the file-name template and returns where it landed.
    @discardableResult
    func saveImage(_ image: CGImage, pixelScale: CGFloat) throws -> URL {
        guard let data = ImageEncoder.pngData(image, pixelScale: pixelScale) else { throw SaveError.encodingFailed }
        let base = FileNamer.baseName(template: fileNameTemplate, date: Date())
        return try withSaveFolder { dir in
            let url = FileNamer.uniqueURL(directory: dir, baseName: base, ext: "png") {
                FileManager.default.fileExists(atPath: $0.path)
            }
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
