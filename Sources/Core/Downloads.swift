import Foundation

/// A course download started by the sync bookmark on a Moodle course page.
/// The browser saves files to ~/Downloads as `TAUdo__<courseID>__<section>__<name>`; TAUdo then files them
/// into the course folder, one subfolder per Moodle section.
struct DownloadManifest: Codable, Hashable, Sendable {
    /// Moodle's internal course id (from the course page).
    var courseID: Int
    /// Course name as shown on the course page.
    var name: String
    /// Section number → section title.
    var sections: [String: String] = [:]
    /// Files the bookmark started downloading.
    var count: Int = 0
    /// Files filed into the course folder so far.
    var filed: Int = 0
    var started: Date = .now
}

enum DownloadOrganizer {
    static let prefix = "TAUdo__"

    struct Item: Equatable {
        var courseID: Int
        /// Section number, or "all" for Moodle's whole-course zip.
        var section: String
        var name: String
    }

    /// Parses a downloaded file name; nil for anything that isn't ours or is still downloading.
    static func parse(_ fileName: String) -> Item? {
        guard fileName.hasPrefix(prefix) else { return nil }
        let lower = fileName.lowercased()
        if [".crdownload", ".download", ".part", ".partial"].contains(where: lower.hasSuffix) { return nil }
        let parts = fileName.dropFirst(prefix.count).components(separatedBy: "__")
        guard parts.count >= 3, let id = Int(parts[0]), !parts[1].isEmpty else { return nil }
        let name = parts.dropFirst(2).joined(separator: "__")
        guard !name.isEmpty else { return nil }
        return Item(courseID: id, section: parts[1], name: name)
    }

    /// Folder inside the course folder: `Moodle/` for the whole-course zip, else `Moodle/<NN> <section title>/`.
    static func subfolder(for item: Item, manifest: DownloadManifest) -> String {
        guard item.section != "all", let n = Int(item.section) else { return "Moodle" }
        let title = safe(manifest.sections[item.section] ?? "")
        return "Moodle/" + String(format: "%02d", n) + (title.isEmpty ? "" : " " + title)
    }

    /// Makes a string usable as a file name (it may come out empty, e.g. from "..").
    static func safe(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet(charactersIn: "/:\\\0")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String(cleaned.prefix(80))
    }

    /// `safe(s)`, or `fallback` when nothing usable is left: a file or folder always gets a name of its own.
    static func name(_ s: String, or fallback: String) -> String {
        let n = safe(s)
        return n.isEmpty ? fallback : n
    }
}
