import Foundation

/// Moves the bookmark's downloads from ~/Downloads into course folders (unzipping zips). Runs off the main thread.
/// Never overwrites: a file that differs from what's already there is saved as "name 2.ext".
enum DownloadMover {
    /// Returns how many downloads were filed per course id.
    static func run(_ jobs: [(DownloadManifest, URL)], downloads: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                    now: Date = .now) -> [Int: Int] {
        let fm = FileManager.default
        let byCourse = Dictionary(jobs.map { ($0.0.courseID, $0) }, uniquingKeysWith: { a, _ in a })
        guard let names = try? fm.contentsOfDirectory(atPath: downloads.path) else { return [:] }
        var moved: [Int: Int] = [:]
        for name in names {
            guard let item = DownloadOrganizer.parse(name), let (manifest, folder) = byCourse[item.courseID] else { continue }
            let src = downloads.appendingPathComponent(name)
            guard isComplete(src, siblings: names, now: now) else { continue }
            let dir = folder.appendingPathComponent(DownloadOrganizer.subfolder(for: item, manifest: manifest), isDirectory: true)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if item.name.lowercased().hasSuffix(".zip") {
                    // Folder downloads and Moodle's course export arrive as zips: unpack beside, never over, your files.
                    let target = item.section == "all" ? dir
                        : dir.appendingPathComponent(DownloadOrganizer.safe(String(item.name.dropLast(4))), isDirectory: true)
                    let staging = fm.temporaryDirectory.appendingPathComponent("TAUdo-unzip-\(UUID().uuidString)")
                    defer { try? fm.removeItem(at: staging) }
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", src.path, staging.path]
                    try p.run(); p.waitUntilExit()
                    guard p.terminationStatus == 0 else { continue }
                    try merge(staging, into: target)
                    try fm.removeItem(at: src)
                } else {
                    try place(src, at: dir.appendingPathComponent(DownloadOrganizer.safe(item.name)))
                }
                moved[item.courseID, default: 0] += 1
            } catch {
                continue
            }
        }
        return moved
    }

    /// Finished downloading: not empty, no in-progress sibling (Firefox keeps an empty placeholder next to "name.part"),
    /// and untouched for a couple of seconds.
    static func isComplete(_ url: URL, siblings: [String], now: Date) -> Bool {
        let name = url.lastPathComponent
        if siblings.contains(where: { $0 == name + ".part" || $0 == name + ".crdownload" || $0 == name + ".download" }) { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else { return false }
        if let modified = attrs[.modificationDate] as? Date, now.timeIntervalSince(modified) < 2 { return false }
        return true
    }

    /// Moves every file under `staging` into `target`, keeping the folder structure and never overwriting.
    static func merge(_ staging: URL, into target: URL) throws {
        let fm = FileManager.default
        // Compare resolved paths: the temporary folder is reached through a symlink (/var → /private/var).
        let base = staging.resolvingSymlinksInPath().pathComponents
        guard let en = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let parts = url.resolvingSymlinksInPath().pathComponents
            guard parts.starts(with: base) else { continue }
            let rel = Array(parts.dropFirst(base.count))
            guard !rel.isEmpty, !rel.contains("__MACOSX") else { continue }
            let dest = rel.reduce(target) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try place(url, at: dest)
        }
    }

    /// Moves `src` to `dest`. If an identical-size file is already there it's a re-download: keep yours, drop the new one.
    /// If a different file is there, the new one becomes "name 2.ext".
    static func place(_ src: URL, at dest: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest.path) else { try fm.moveItem(at: src, to: dest); return }
        let size = { (u: URL) in (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int) ?? -1 }
        if size(dest) == size(src) { try fm.removeItem(at: src); return }
        let base = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
        for n in 2... {
            let candidate = dest.deletingLastPathComponent().appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fm.fileExists(atPath: candidate.path) { try fm.moveItem(at: src, to: candidate); return }
        }
    }
}
