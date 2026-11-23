import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var data: AppData { didSet { save() } }
    var now = Date()
    var syncing = false
    var feedError: String?
    var calendarStatus: String?
    /// Set while waiting for the export link to be copied in the browser.
    var connectStatus: String?
    /// Files behind each course's cubes (lecture videos, pset folders, …), by course id.
    var files: [UUID: CourseFiles] = [:]
    /// Set if the saved state couldn't be read at launch.
    var loadError: String?

    private let calendar = CalendarSync()
    private var loop: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var refreshAgain = false
    /// Alarms are stripped from the calendar once after calendar sync is turned off.
    private var calendarAlarmsCleared = false
    private let persist: Bool

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TAUdo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    init(data: AppData? = nil, persist: Bool = true) {
        self.persist = persist
        if let data { self.data = data }
        else if let raw = try? Data(contentsOf: Self.fileURL) {
            do {
                self.data = try Self.decoder.decode(AppData.self, from: raw)
                save()  // persist defaults filled in for new fields (e.g. the bookmark secret)
            }
            catch {
                // Never silently replace your progress: keep the unreadable file next to the new one.
                let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
                let backup = Self.fileURL.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(stamp).json")
                try? FileManager.default.copyItem(at: Self.fileURL, to: backup)
                self.data = .initial
                loadError = "Your saved data couldn't be read, so TAUdo started fresh. The old file is kept at \(backup.path)."
                save()
            }
        }
        else { self.data = .initial; save() }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(max(5, self.data.settings.refreshMinutes) * 60))
            }
        }
        Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); self?.now = .now }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.now = .now; await self?.refresh() }
        }
        if data.settings.notifications && !data.settings.calendarSync { Task { _ = await Notifier.requestAuthorization() } }
        if !persist { Task { await scanFiles() } }
        push()
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func save() {
        guard persist, let raw = try? Self.encoder.encode(data) else { return }
        // The export link is a bearer token for your Moodle calendar: keep the file private.
        FileManager.default.createFile(atPath: Self.fileURL.path, contents: raw, attributes: [.posixPermissions: 0o600])
    }

    // MARK: Sync

    func refresh() async {
        guard persist else { return }
        // A refresh requested mid-sync (e.g. a new export link) runs right after the current one.
        guard !syncing else { refreshAgain = true; return }
        syncing = true; defer { syncing = false }
        repeat {
            refreshAgain = false
            let url = data.settings.exportURL
            if !url.isEmpty {
                do {
                    let events = try await MoodleFeed.fetch(url)
                    data.mergeFeed(events, now: .now)
                    data.lastSync = .now
                    feedError = nil
                } catch {
                    feedError = error.localizedDescription
                }
            }
            await scanFiles()
            data.autoLinkCourses(files: files)
        } while refreshAgain
        now = .now
        push()
    }

    /// Indexes course folders off the main thread.
    func scanFiles() async {
        let folders = data.courses.compactMap { c in data.folder(for: c).map { (c.id, $0) } }
        let result = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: folders.map { ($0.0, CourseFiles.scan($0.1)) })
        }.value
        if result != files { files = result }
    }

    /// Refreshes when opening the panel if the data is older than 10 minutes.
    func refreshIfStale() {
        if data.lastSync.map({ Date().timeIntervalSince($0) > 600 }) ?? true { Task { await refresh() } }
    }

    private var moodleHost: String { URL(string: data.settings.moodleBaseURL)?.host ?? "moodle.tau.ac.il" }
    private var connectTask: Task<Void, Never>?

    /// Opens Moodle's export page in the default browser and takes the link as soon as it's copied.
    func connect() {
        let base = data.settings.moodleBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: base + "/calendar/export.php") { NSWorkspace.shared.open(url) }
        connectStatus = "In the browser: log in, choose All events + Custom range, click Get calendar URL, then copy the link."
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            guard let host = self?.moodleHost,
                  let link = await MoodleConnect.watchClipboard(host: host, until: .now.addingTimeInterval(15 * 60)) else {
                if !Task.isCancelled { self?.connectStatus = nil }
                return
            }
            self?.setExportLink(link)
        }
    }

    private func setExportLink(_ link: String) {
        connectTask?.cancel()
        data.settings.exportURL = link
        connectStatus = nil
        Task { await refresh() }
    }

    /// taudo://sync from the bookmarklet.
    func handle(_ url: URL) {
        // Only accept data from this install's bookmark, for the configured Moodle site.
        guard let p = MoodleConnect.payload(from: url), p.key == data.settings.syncKey,
              URL(string: p.base)?.host == moodleHost else { return }
        data.settings.moodleBaseURL = p.base
        data.moodleCourseNames.merge(p.courses ?? [:]) { _, new in new }
        data.autoLinkCourses(files: files)
        data.applySubmissions(p.submittedIDs)
        data.lastStatusCheck = .now
        if let s = p.exportURL, let link = MoodleConnect.exportLink(s, host: moodleHost) { setExportLink(link) }
        else { push() }
    }

    /// Pushes current state to Apple Calendar and reminders. Debounced: clicking through cubes triggers one push.
    func push() {
        let previous = pushTask
        previous?.cancel()
        pushTask = Task { [weak self] in
            // One push at a time: a superseded one stops early, and this one starts after it.
            await previous?.value
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled, persist else { return }
            let s = data.settings
            let deadlines = data.deadlines()
            if s.calendarSync {
                calendarAlarmsCleared = false
                await syncCalendar(deadlines)
            } else if s.calendarID != nil, calendar.hasAccess, !calendarAlarmsCleared {
                // Sync was turned off: leave the events, but drop their alerts so you aren't reminded twice.
                calendarAlarmsCleared = true
                await syncCalendar(deadlines, alarms: false)
            }
            // With calendar sync working, the calendar's alerts remind you (and reach your iPhone via iCloud).
            let calendarReminds = s.calendarSync && calendar.hasAccess
            await Notifier.reschedule(deadlines, courseNames: Dictionary(uniqueKeysWithValues: data.courses.enumerated().map { ($0.offset, $0.element.name) }),
                                      leadMinutes: s.reminderMinutes, enabled: s.notifications && !calendarReminds)
        }
    }

    private func syncCalendar(_ deadlines: [Deadline], alarms: Bool = true) async {
        do {
            if !calendar.hasAccess, !(try await calendar.requestAccess()) {
                calendarStatus = "No calendar access. Allow TAUdo in System Settings › Privacy & Security › Calendars."
                return
            }
            let cal = try calendar.calendar(id: data.settings.calendarID, name: data.settings.calendarName)
            if data.settings.calendarID != cal.calendarIdentifier { data.settings.calendarID = cal.calendarIdentifier }
            var planned = plannedEvents(deadlines)
            if !alarms { for i in planned.indices { planned[i].alarms = [] } }
            let r = try calendar.sync(planned, into: cal)
            calendarStatus = "Calendar “\(cal.title)” up to date" + (r.created + r.updated + r.deleted > 0 ? " (+\(r.created) ~\(r.updated) −\(r.deleted))" : "")
        } catch {
            calendarStatus = "Calendar sync failed: \(error.localizedDescription)"
        }
    }

    func plannedEvents(_ deadlines: [Deadline]) -> [CalendarSync.Planned] {
        let byUID = Dictionary(deadlines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let s = data.settings
        var events = data.events.filter { s.calendarIncludesAllEvents || byUID[$0.uid] != nil }
        events += deadlines.filter(\.isManual).map(\.event)
        return events.map { e in
            let d = byUID[e.uid]
            let course: String? = (d?.courseIndex ?? data.courseIndex(for: e)).map { data.courses[$0].name } ?? e.courseKey.map(data.courseLabel)
            var title = (course.map { "[\($0)] " } ?? "") + Classifier.cleanTitle(e.summary)
            var start = e.start, alarms: [TimeInterval] = []
            if let d {
                title = (d.isDone ? "✅ " : d.due < now ? "🔴 " : "⬜ ") + title
                if e.end == e.start && !e.isAllDay { start = e.end.addingTimeInterval(-30 * 60) }  // show deadlines as a 30-min block
                if !d.isDone { alarms = s.reminderMinutes.map { Double($0) * 60 + e.end.timeIntervalSince(start) } }
            }
            return .init(uid: e.uid, title: title, start: start, end: e.end, isAllDay: e.isAllDay,
                         notes: e.description, url: e.url.flatMap(URL.init(string:)), alarms: alarms)
        }
    }

    // MARK: Derived

    var deadlines: [Deadline] { data.deadlines() }

    /// Open deadlines: everything not done that is upcoming or at most a week overdue.
    var open: [Deadline] {
        deadlines.filter { !$0.isDone && $0.due > now.addingTimeInterval(-7 * 86400) }
    }

    var next: Deadline? { open.first { $0.due >= now } }
    var overdueCount: Int { open.filter { $0.due < now }.count }

    func courseName(_ d: Deadline) -> String {
        d.courseIndex.map { data.courses[$0].name } ?? data.courseLabel(d.event.courseKey)
    }

    /// Moodle courses with deadlines that aren't linked to a tracker course yet.
    var unlinkedMoodleCourses: [String] {
        Set(deadlines.filter { $0.courseIndex == nil && !$0.isManual }.compactMap(\.event.courseKey)).sorted()
    }

    func link(_ key: String, to courseID: UUID) {
        guard let i = data.courses.firstIndex(where: { $0.id == courseID }) else { return }
        data.courses[i].moodleKey = key
        push()
    }

    /// e.g. "Calculus HW 4 · 2d"
    func menuTitle(_ d: Deadline) -> String {
        let course = courseName(d).split(separator: " ").first.map(String.init) ?? ""
        let what = d.isExam ? "Exam" : Classifier.assignmentNumber(d.event.summary).map { "HW \($0)" } ?? String(d.title.prefix(14))
        return [course, what].filter { !$0.isEmpty }.joined(separator: " ") + " · " + Self.remaining(d.due, now: now)
    }

    static func remaining(_ due: Date, now: Date) -> String {
        let s = due.timeIntervalSince(now)
        if s < 0 { return "overdue" }
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    // MARK: Actions

    func cycle(_ ci: Int, _ ti: Int, _ i: Int) {
        data.courses[ci].tracks[ti].cells[i] = data.courses[ci].tracks[ti].cells[i].next
        push()
    }

    func set(_ ci: Int, _ ti: Int, _ i: Int, _ s: CellState) {
        data.courses[ci].tracks[ti].cells[i] = s
        push()
    }

    /// "The class is here": stores the difference from the computed position, so it keeps advancing.
    func setClassPosition(_ ci: Int, _ ti: Int, to pos: Int) {
        var t = data.courses[ci].tracks[ti]
        t.classOffset = 0
        let computed = Pacing.classPosition(t, links: data.homeworkLinks(course: ci), settings: data.settings, now: now)
        data.courses[ci].tracks[ti].classOffset = pos - computed
    }

    func markDone(uid: String) {
        guard let d = deadlines.first(where: { $0.id == uid }), !d.isDone else { return }
        data.setDone(d, true)
        push()
    }

    func toggle(_ d: Deadline) {
        data.setDone(d, !d.isDone)
        push()
    }

    func hide(_ d: Deadline) {
        if d.isManual { data.manual.removeAll { $0.uid == d.id } } else { data.hiddenUIDs.insert(d.id) }
        push()
    }
}
