import Foundation

/// Expands templates like `Screenshot {yyyy-MM-dd} at {HH.mm.ss}`.
/// Anything inside braces is a DateFormatter pattern; everything else is literal.
public enum FileNamer {
    public static let defaultTemplate = "Screenshot {yyyy-MM-dd} at {HH.mm.ss}"

    public static func baseName(template: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                // Unbalanced brace: keep the remainder literally.
                result += rest[open...]
                rest = ""
                break
            }
            formatter.dateFormat = String(rest[afterOpen..<close])
            result += formatter.string(from: date)
            rest = rest[rest.index(after: close)...]
        }
        result += rest

        let cleaned = result
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Screenshot" : cleaned
    }

    /// `name.png`, or `name 2.png`, `name 3.png`… if taken.
    public static func uniqueURL(
        directory: URL,
        baseName: String,
        ext: String,
        exists: (URL) -> Bool
    ) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var n = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(baseName) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
