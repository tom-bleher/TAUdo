import AppKit
import EventKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    static let log = Logger(subsystem: "io.github.tombleher.TAUdo", category: "sync")
    var data: AppData { didSet { save() } }
    var now = Date()
    var feedError: String?
    var calendarStatus: String?
    /// Calendars TAUdo may write to (empty until calendar access is granted).
    var calendarChoices: [CalendarSync.Choice] = []
    /// Set while waiting for the export link to be copied in the browser.
    var connectStatus: String?
    /// Files behind each course's cubes (pset folders, recitation notes), by course id.
    var files: [UUID: CourseFiles] = [:]
    /// Set if the saved state couldn't be read at launch.
    var loadError: String?
    /// While the panel is open the menu bar label is frozen: macOS closes a menu bar panel
    /// when its status item changes size underneath it.
    private(set) var panelOpen = false
    private var frozenLabel = MenuLabel(overdue: 0, title: nil)

    private let calendar = CalendarSync()
    private var loop: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
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
                loadError = String(localized: "Your saved data couldn't be read, so TAUdo started fresh. The old file is kept at \(backup.path).")
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
        // A calendar account added in System Settings (e.g. Google) shows up in the calendar picker right away.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendarChoices() }
        }
        // New users are asked in the welcome window; existing ones at launch (asks only once).
        if data.settings.notifications && data.onboarded { Task { _ = await Notifier.requestAuthorization() } }
        if !persist { Task { await scanFiles() } }
        Notifier.sound = data.settings.notificationSound
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

    var syncing: Bool { syncTask != nil }

    /// Syncs Moodle, exams and course files. Returns once the data reflects everything changed before the call:
    /// a refresh requested mid-sync (e.g. a new export link) runs the sync once more and waits for that.
    func refresh() async {
        guard persist else { return }
        if let running = syncTask { refreshAgain = true; await running.value; return }
        let task = Task { await sync() }
        syncTask = task
        await task.value
    }

    private func sync() async {
        defer { syncTask = nil }
        repeat {
            refreshAgain = false
            let url = data.settings.exportURL
            if !url.isEmpty {
                do {
                    let events = try await MoodleFeed.fetch(url)
                    announce(data.mergeFeed(events, now: .now))
                    data.lastSync = .now
                    feedError = nil
                } catch {
                    feedError = error.localizedDescription
                }
            }
            await refreshExams()
            await scanFiles()
            data.autoLinkCourses(files: files)
            await organizeDownloads()
        } while refreshAgain
        now = .now
        push()
    }

    /// Exam dates from Arazim, fetched at most daily (the catalog is a few MB).
    /// On failure the last known dates stay.
    private func refreshExams() async {
        guard data.settings.fetchExams, data.examsFetched.map({ Date().timeIntervalSince($0) > 86400 }) ?? true else { return }
        let keys = Set(data.courses.compactMap(\.moodleKey)).union(data.moodleCourseKeys)
        guard !keys.isEmpty else { return }
        let url = Arazim.catalogURL(semesterStart: data.settings.semesterStart)
        do {
            let (body, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            data.exams = try await Task.detached(priority: .utility) { try Arazim.exams(catalog: body, moodleKeys: keys) }.value
            data.examsFetched = .now
        } catch {}
    }

    /// Indexes course folders off the main thread.
    func scanFiles() async {
        let folders = data.courses.compactMap { c in data.folder(for: c).map { (c.id, $0) } }
        let result = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: folders.map { ($0.0, CourseFiles.scan($0.1)) })
        }.value
        if result != files { files = result }
    }

    /// Alerts for deadlines Moodle just posted or moved.
    private func announce(_ c: AppData.FeedChanges) {
        guard data.settings.notifications, data.settings.alertChanges else { return }
        let name = { (e: MoodleEvent) in self.data.courseIndex(for: e).map { self.data.courses[$0].name } ?? self.data.courseLabel(e.courseKey) }
        if c.added.count > 3 {
            Notifier.post(String(localized: "\(c.added.count) new deadlines on Moodle"),
                          c.added.map { "• \(Classifier.cleanTitle($0.summary)) · \(name($0))" }.joined(separator: "\n"))
        } else {
            for e in c.added {
                Notifier.post(String(localized: "New: \(Classifier.cleanTitle(e.summary))"),
                              name(e) + " · " + String(localized: "Due \(e.due.medium(time: !e.isAllDay))"), id: "new." + e.uid)
            }
        }
        for m in c.moved {
            Notifier.post(String(localized: "Moved: \(Classifier.cleanTitle(m.event.summary))"),
                          name(m.event) + " · " + String(localized: "Now due \(m.event.due.medium(time: !m.event.isAllDay)) (was \(m.from.medium(time: !m.event.isAllDay)))"), id: "moved." + m.event.uid)
        }
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
        connectStatus = String(localized: "In the browser: log in, choose All events and a custom range, click Get calendar URL, then copy the link.")
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            guard let host = self?.moodleHost,
                  let link = await MoodleConnect.watchClipboard(host: host, until: .now.addingTimeInterval(15 * 60)) else {
                if !Task.isCancelled { self?.connectStatus = nil }
                return
            }
            self?.setExportLink(link)
            await self?.refresh()
        }
    }

    private func setExportLink(_ link: String) {
        connectTask?.cancel()
        data.settings.exportURL = link
        connectStatus = nil
    }

    /// taudo://sync from the bookmarklet.
    func handle(_ url: URL) {
        // Only accept data from this install's bookmark, for the configured Moodle site.
        guard let p = MoodleConnect.payload(from: url), URL(string: p.base)?.host == moodleHost else { return }
        guard p.key == data.settings.syncKey else {
            Notifier.post(String(localized: "This TAUdo bookmark is out of date"),
                          String(localized: "Install it again from Settings › Moodle › Install sync bookmark…"), id: "bookmark.stale")
            return
        }
        data.settings.moodleBaseURL = p.base
        data.moodleCourseNames.merge(p.courses ?? [:]) { _, new in new }
        data.autoLinkCourses(files: files)
        data.lastStatusCheck = .now
        if let t = p.took { Self.log.notice("bookmark sync took \(t.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) ms" }.joined(separator: ", "), privacy: .public)") }
        // Replace per course: a course whose block didn't answer this time keeps its last list.
        data.recordings.merge(p.validRecordings.filter { !$0.value.isEmpty }) { _, new in new }
        if (p.v ?? 1) < 4 {
            Notifier.post(String(localized: "Update your TAUdo bookmark"),
                          String(localized: "The new bookmark tells which assignments you've submitted more reliably and finds each course's Panopto recordings. Install it again from Settings › Moodle."), id: "bookmark.old")
        }
        if let dl = p.download, dl.count > 0 {
            data.downloads.removeAll { $0.courseID == dl.courseID }
            data.downloads.append(DownloadManifest(courseID: dl.courseID, name: dl.name, sections: dl.sections ?? [:], count: dl.count))
            watchDownloads()
        }
        if let s = p.exportURL, let link = MoodleConnect.exportLink(s, host: moodleHost) { setExportLink(link) }
        // Submissions apply to the deadlines TAUdo has: fetch the feed first, so a first sync (or one with a new link)
        // has them.
        Task {
            await refresh()
            data.applySubmissions(Set(p.submitted ?? []))
            push()
        }
    }

    // MARK: Course downloads

    private var downloadWatch: Task<Void, Never>?

    /// Files the bookmark's downloads as they land in ~/Downloads (checks every few seconds for 5 minutes).
    func watchDownloads() {
        downloadWatch?.cancel()
        downloadWatch = Task { [weak self] in
            for _ in 0..<100 {
                guard let self, !Task.isCancelled else { return }
                await self.organizeDownloads()
                if self.data.downloads.isEmpty { return }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Where a downloaded course goes: its tracked course's folder, else <coursework folder>/<course>,
    /// else ~/Downloads/TAUdo/<course>.
    func folder(for m: DownloadManifest) -> URL {
        let course = data.course(matching: m.name).map { data.courses[$0] }
        if let course, let f = data.folder(for: course) { return f }
        let name = DownloadOrganizer.safe(course?.name ?? AppData.readableName(m.name))
        let root = data.settings.courseworkFolder.isEmpty
            ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("TAUdo")
            : URL(fileURLWithPath: (data.settings.courseworkFolder as NSString).expandingTildeInPath)
        return root.appendingPathComponent(name, isDirectory: true)
    }

    func organizeDownloads() async {
        guard !data.downloads.isEmpty else { return }
        let jobs = data.downloads.map { ($0, folder(for: $0)) }
        let moved = await Task.detached(priority: .utility) { DownloadMover.run(jobs) }.value
        for (m, folder) in jobs {
            let n = moved[m.courseID] ?? 0
            guard n > 0, let i = data.downloads.firstIndex(where: { $0.courseID == m.courseID }) else { continue }
            data.downloads[i].filed += n
            let total = data.downloads[i].filed
            // One notification per course download, updated as files arrive.
            Notifier.post(String(localized: "Saved \(total) files from \(AppData.readableName(m.name))"),
                          folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), id: "dl.\(m.courseID)", open: folder)
            if total >= data.downloads[i].count { data.downloads.remove(at: i) }
        }
        // Give up on downloads that never arrived.
        data.downloads.removeAll { Date().timeIntervalSince($0.started) > 7 * 86400 }
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
            Notifier.sound = s.notificationSound
            // With calendar sync working, the calendar's alerts remind you (and reach your iPhone via iCloud).
            // If it failed, TAUdo's own reminders do.
            var calendarReminds = false
            if s.calendarSync {
                calendarAlarmsCleared = false
                calendarReminds = await syncCalendar()
            } else if let id = s.calendarID, calendar.hasAccess, !calendarAlarmsCleared {
                // Sync was turned off: leave the events, but drop their alerts so you aren't reminded twice.
                calendarAlarmsCleared = true
                do { try calendar.removeAlarms(fromCalendar: id) }
                catch { calendarStatus = String(localized: "Calendar sync failed: \(error.localizedDescription)") }
            }
            // Read after the awaits above, so course indices match the courses as they are now.
            let deadlines = data.deadlines()
            let names = Dictionary(deadlines.map { ($0.id, self.courseName($0)) }, uniquingKeysWith: { a, _ in a })
            await Notifier.reschedule(.init(deadlines: deadlines, courseName: { names[$0.id] ?? "" },
                                            leadMinutes: s.reminderMinutes, reminders: s.notifications && !calendarReminds,
                                            digestHour: s.notifications ? s.digestHour : nil))
        }
    }

    /// Mirrors the deadlines into the calendar. Returns whether it worked (so its alerts will fire).
    private func syncCalendar() async -> Bool {
        do {
            if !calendar.hasAccess, !(try await calendar.requestAccess()) {
                calendarStatus = String(localized: "No calendar access. Allow TAUdo in System Settings › Privacy & Security › Calendars.")
                return false
            }
            let cal = try calendar.calendar(id: data.settings.calendarID, name: data.settings.calendarName)
            refreshCalendarChoices()
            if data.settings.calendarID != cal.calendarIdentifier { data.settings.calendarID = cal.calendarIdentifier }
            // Read after the access prompt, so course indices match the courses as they are now.
            let r = try calendar.sync(plannedEvents(data.deadlines()), into: cal, keepBefore: data.settings.semesterStart)
            calendarStatus = String(localized: "Calendar “\(cal.title)” is up to date") + (r.created + r.updated + r.deleted > 0 ? " (+\(r.created) ~\(r.updated) −\(r.deleted))" : "")
            return true
        } catch {
            calendarStatus = String(localized: "Calendar sync failed: \(error.localizedDescription)")
            return false
        }
    }

    func refreshCalendarChoices() {
        calendarChoices = calendar.hasAccess ? calendar.writableCalendars() : []
    }

    /// Moves TAUdo's events to another calendar (nil: a new calendar of its own), clearing them from the old one.
    func useCalendar(_ id: String?) {
        let old = data.settings.calendarID
        guard id != old else { return }
        if let old, calendar.hasAccess {
            do { try calendar.removeOurEvents(fromCalendar: old) }
            catch { calendarStatus = String(localized: "Calendar sync failed: \(error.localizedDescription)") }
        }
        data.settings.calendarID = id
        push()
    }

    func plannedEvents(_ deadlines: [Deadline]) -> [CalendarSync.Planned] {
        let byUID = Dictionary(deadlines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let s = data.settings
        // Courses you said aren't yours and deadlines you hid stay out of the calendar too.
        let hidden = data.ignoredCourseKeys
        var events = data.events
            .filter { !($0.courseKey.map(hidden.contains) ?? false) && !data.hiddenUIDs.contains($0.uid) }
            .filter { s.calendarIncludesAllEvents || byUID[$0.uid] != nil }
        events += deadlines.filter(\.isExtra).map(\.event)
        return events.map { e in
            let d = byUID[e.uid]
            let course: String? = (d?.courseIndex ?? data.courseIndex(for: e)).map { data.courses[$0].name } ?? e.courseKey.map(data.courseLabel)
            var title = (course.map { "[\($0)] " } ?? "") + Classifier.cleanTitle(e.summary)
            if let d { title = (d.isDone ? "✅ " : d.due < now ? "🔴 " : "⬜ ") + title }
            // All-day events on the day they fall; the time goes in the title.
            let moment = d != nil ? e.end : e.start
            let day = e.isAllDay ? Calendar.current.startOfDay(for: e.start) : AllDay.day(of: moment, isDeadline: d != nil)
            if !e.isAllDay { title += " · " + AllDay.time(moment, day: day) }
            let alarms = d.map { $0.isDone ? [] : AllDay.alarms(leadMinutes: s.reminderMinutes, due: e.end, day: day) } ?? []
            return .init(uid: e.uid, title: title, start: day, end: day,
                         isAllDay: true, notes: e.description, url: e.url.flatMap(URL.init(string:)), alarms: alarms)
        }
    }

    // MARK: Menu bar label

    struct MenuLabel: Equatable { var overdue: Int; var title: String? }

    var menuLabel: MenuLabel {
        if panelOpen { return frozenLabel }
        let title: String? = switch data.settings.menuBar {
        case .icon: nil
        case .timeLeft: next.map { Self.remaining($0.due, now: now) }
        case .deadline: next.map(menuTitle)
        }
        return MenuLabel(overdue: overdueCount, title: title)
    }

    func panelDidOpen() { frozenLabel = menuLabel; panelOpen = true }
    func panelDidClose() { panelOpen = false }

    // MARK: Derived

    var deadlines: [Deadline] { data.deadlines() }

    private var due: [Deadline] { data.dueDeadlines() }

    /// Upcoming exams, for the Exams tab.
    var exams: [Deadline] { deadlines.filter { $0.isExam && $0.due >= now } }

    /// Not done and missed within the last week.
    var overdue: [Deadline] {
        due.filter { !$0.isDone && $0.due < now && $0.due > now.addingTimeInterval(-7 * 86400) }
    }

    /// Open deadlines shown in the panel: upcoming ones, plus overdue ones if you chose to see them.
    var open: [Deadline] {
        (data.settings.showOverdue ? overdue : []) + due.filter { !$0.isDone && $0.due >= now }
    }

    var next: Deadline? { open.first { $0.due >= now } }

    /// Ticked deadlines that are still current (due within the last week or later), so a tick can be undone.
    var completed: [Deadline] {
        due.filter { $0.isDone && $0.due > now.addingTimeInterval(-7 * 86400) }
    }
    /// Shown in the menu bar only when overdue deadlines are shown.
    var overdueCount: Int { data.settings.showOverdue ? overdue.count : 0 }

    func courseName(_ d: Deadline) -> String {
        d.courseIndex.flatMap { data.courses.indices.contains($0) ? data.courses[$0].name : nil } ?? data.courseLabel(d.event.courseKey)
    }

    /// Moodle courses with deadlines that aren't linked to a tracker course yet.
    var unlinkedMoodleCourses: [String] {
        Set(deadlines.filter { $0.courseIndex == nil && !$0.isExtra }.compactMap(\.event.courseKey)).sorted()
    }

    func addCourse(fromMoodle key: String) {
        data.addCourse(fromMoodle: key)
        push()
    }

    /// "Not my course": its deadlines stop showing (undo in Settings › Moodle).
    func ignore(moodleCourse key: String) {
        data.ignoredCourseKeys.insert(key)
        push()
    }

    func finishOnboarding() { data.onboarded = true }

    /// Moodle courses you said aren't yours that still have events in the feed (last year's don't count).
    var hiddenCourseCount: Int {
        data.ignoredCourseKeys.intersection(data.events.compactMap(\.courseKey)).count
    }

    /// Deadlines hidden one by one with "Hide (not mine)" that are still in the feed.
    var hiddenDeadlineCount: Int { data.hiddenUIDs.intersection((data.events + data.exams).map(\.uid)).count }

    func showHiddenDeadlines() {
        data.hiddenUIDs = []
        push()
    }

    func show(moodleCourse key: String) {
        data.ignoredCourseKeys.remove(key)
        push()
    }

    /// An exam or deadline of your own, added from the panel or Settings.
    func addDeadline(title: String, due: Date, courseID: UUID?) {
        data.manual.append(ManualDeadline(title: title, due: due, courseID: courseID))
        push()
    }

    func link(_ key: String, to courseID: UUID) {
        guard let i = data.courses.firstIndex(where: { $0.id == courseID }) else { return }
        data.courses[i].moodleKey = key
        push()
    }

    /// e.g. "Calculus HW 4 · 2d"
    func menuTitle(_ d: Deadline) -> String {
        let course = courseName(d).split(separator: " ").first.map(String.init) ?? ""
        let what = d.isExam ? String(localized: "Exam") : Classifier.assignmentNumber(d.event.summary).map { String(localized: "HW \($0)") } ?? String(d.title.prefix(14))
        return [course, what].filter { !$0.isEmpty }.joined(separator: " ") + " · " + Self.remaining(d.due, now: now)
    }

    static func remaining(_ due: Date, now: Date) -> String {
        let s = due.timeIntervalSince(now)
        if s < 0 { return String(localized: "overdue") }
        if s < 3600 { return String(localized: "\(max(1, Int(s / 60)))m", comment: "minutes left") }
        if s < 86400 { return String(localized: "\(Int(s / 3600))h", comment: "hours left") }
        return String(localized: "\(Int(s / 86400))d", comment: "days left")
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
