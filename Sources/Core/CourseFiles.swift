import Foundation

/// Finds the files behind each cube in a course folder, e.g.
/// `psets/pset7` → Homework 7, `recitations/rec3.pdf` → Recitation 3.
/// Recordings aren't looked for here: cubes open them on Panopto (see Recordings).
struct CourseFiles: Sendable, Equatable {
    var items: [TrackKind: [Int: [URL]]] = [:]
    /// Long digit runs in file names (TAU course codes like 0366110001), for linking Moodle courses.
    var codes: Set<String> = []

    func urls(_ kind: TrackKind, _ number: Int) -> [URL] { items[kind]?[number] ?? [] }

    private static let skip: Set<String> = ["_to_delete", "build", "node_modules", "scripts", "textbooks", "transcriptions", "boards", "work", "info"]

    /// Which row a path belongs to, from its folder names.
    static func kind(_ components: [String]) -> TrackKind? {
        for c in components.dropLast().reversed() {
            let c = c.lowercased()
            if c.hasPrefix("pset") || c.hasPrefix("hw") || c.hasPrefix("homework") || c.hasPrefix("תרגילי") { return .homework }
            if c.hasPrefix("recitation") || c.hasPrefix("tutorial") || c.hasPrefix("תרגול") { return .recitation }
        }
        return nil
    }

    /// The item number in a name: the first 1–2 digit run that isn't part of a longer number ("01 - 0366110001 - …" → 1).
    static func number(_ name: String) -> Int? {
        guard let r = name.range(of: #"(?<!\d)\d{1,2}(?!\d)"#, options: .regularExpression), let n = Int(name[r]), n > 0 else { return nil }
        return n
    }

    static func scan(_ root: URL, maxFiles: Int = 20_000) -> CourseFiles {
        var out = CourseFiles()
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
        var seen = 0
        // Path components of the course folder as the enumerator spells it (it may resolve a symlink in `root`,
        // e.g. /var → /private/var): the first item it returns is a direct child.
        var rootDepth: Int?
        /// Homework folders found so far (paths relative to the course folder).
        var homework: [String] = []
        for case let url as URL in en {
            seen += 1
            if seen > maxFiles { break }
            let depth = rootDepth ?? url.deletingLastPathComponent().pathComponents.count
            rootDepth = depth
            let rel = Array(url.pathComponents.dropFirst(depth))
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir && (skip.contains(url.lastPathComponent.lowercased()) || rel.count >= 4) { en.skipDescendants(); continue }
            let name = url.deletingPathExtension().lastPathComponent
            for r in name.matches(of: #/\d{8,}/#) { out.codes.insert(String(r.output)) }
            guard let kind = kind(rel), let n = number(name) else { continue }
            let ext = url.pathExtension.lowercased()
            switch kind {
            // A homework item is its pset folder (statement, your .lyx and solution PDF live inside). What's inside
            // belongs to it: psets/pset1/q2 isn't homework 2.
            case .homework:
                let path = rel.joined(separator: "/")
                guard isDir, rel.count >= 2, !homework.contains(where: { path.hasPrefix($0 + "/") }) else { continue }
                homework.append(path)
            case .recitation:
                guard !isDir, ext == "pdf" else { continue }
            case .lecture, .other:
                continue
            }
            out.items[kind, default: [:]][n, default: []].append(url)
        }
        for (k, byNum) in out.items { for (n, urls) in byNum { out.items[k]![n] = urls.sorted { $0.path < $1.path } } }
        return out
    }
}

extension AppData {
    /// Links unmapped Moodle courses to tracker courses: by a course code found in the course's files,
    /// or by name (all the tracker name's words appear in Moodle's course name). Only unambiguous matches.
    mutating func autoLinkCourses(files: [UUID: CourseFiles]) {
        let digits = { (s: String) in s.filter(\.isNumber) }
        let words = AppData.nameWords
        // Not the courses you said aren't yours: another group's copy would grab your course by name.
        let keys = Set(moodleCourseKeys).subtracting(courses.compactMap(\.moodleKey))
        for key in keys.sorted() {
            let free = courses.indices.filter { courses[$0].moodleKey == nil }
            let byCode = free.filter { i in
                let d = digits(key)
                return d.count >= 8 && (files[courses[i].id]?.codes.contains { $0.hasPrefix(d) || d.hasPrefix($0) } ?? false)
            }
            // Moodle's course label ("0321213001 - שיטות בפיזיקה עיונית 1") already carries the name.
            let full = moodleCourseNames[key] ?? key
            let byName = free.filter { i in
                let w = words(courses[i].name)
                return !w.isEmpty && w.isSubset(of: words(full))
            }
            if let i = (byCode.count == 1 ? byCode : byName.count == 1 ? byName : []).first { courses[i].moodleKey = key }
        }
    }
}
