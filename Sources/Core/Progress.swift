import Foundation

/// A Moodle deadline, linked to a homework cube when its course and number can be matched.
struct Deadline: Identifiable, Hashable, Sendable {
    struct Cell: Hashable, Sendable { var track: Int; var index: Int }

    var event: MoodleEvent
    var courseIndex: Int?
    /// The matching homework cube.
    var cell: Cell?
    var isDone: Bool

    var id: String { event.uid }
    var due: Date { event.due }
    var title: String { Classifier.cleanTitle(event.summary) }
    var isExam: Bool { Classifier.isExam(event.summary) }
    var isManual: Bool { event.uid.hasPrefix("manual-") }
}

extension AppData {
    func courseIndex(for e: MoodleEvent) -> Int? {
        guard let key = e.courseKey else { return nil }
        return courses.firstIndex { $0.moodleKey == key }
    }

    /// Deadlines in the feed, minus courses you said aren't yours.
    var problemSets: [MoodleEvent] {
        events.filter { !($0.courseKey.map(ignoredCourseKeys.contains) ?? false) }
            .filter { Classifier.isProblemSet(summary: $0.summary, description: $0.description) }
    }

    /// Moodle courses in the feed (each Moodle course is one CATEGORIES value), excluding ignored ones.
    var moodleCourseKeys: [String] {
        Set(events.compactMap(\.courseKey)).subtracting(ignoredCourseKeys).sorted()
    }

    /// A new tracked course for a Moodle course, already linked, named like Moodle names it.
    mutating func addCourse(fromMoodle key: String) {
        guard !courses.contains(where: { $0.moodleKey == key }) else { return }
        var c = Course.standard(courseLabel(key))
        c.moodleKey = key
        courses.append(c)
    }

    /// Homework cube index → Moodle deadline, per course. With duplicates (e.g. a resubmission), the last due date wins.
    func homeworkLinks(course ci: Int) -> [Int: MoodleEvent] {
        guard let key = courses[ci].moodleKey,
              let hw = courses[ci].tracks.firstIndex(where: { $0.kind == .homework }) else { return [:] }
        var out: [Int: MoodleEvent] = [:]
        for e in problemSets where e.courseKey == key {
            guard let n = Classifier.assignmentNumber(e.summary), n <= courses[ci].tracks[hw].count else { continue }
            if let old = out[n - 1], old.due > e.due { continue }
            out[n - 1] = e
        }
        return out
    }

    func deadlines() -> [Deadline] {
        var linked: [String: (Int, Int, Int)] = [:]  // uid → (course, track, cell)
        for ci in courses.indices {
            guard let hw = courses[ci].tracks.firstIndex(where: { $0.kind == .homework }) else { continue }
            for (i, e) in homeworkLinks(course: ci) { linked[e.uid] = (ci, hw, i) }
        }
        let moodle = problemSets.filter { !hiddenUIDs.contains($0.uid) }.map { e in
            // Done means submitted (ticked here or reported by Moodle), not "solved": when you study ahead,
            // a cube can be done long before this year's deadline is handed in.
            if let (ci, t, i) = linked[e.uid] {
                return Deadline(event: e, courseIndex: ci, cell: .init(track: t, index: i), isDone: doneUIDs.contains(e.uid))
            }
            return Deadline(event: e, courseIndex: courseIndex(for: e), cell: nil, isDone: doneUIDs.contains(e.uid))
        }
        let own = manual.map { m in
            Deadline(event: MoodleEvent(uid: m.uid, summary: m.title, start: m.due, end: m.due),
                     courseIndex: courses.firstIndex { $0.id == m.courseID }, cell: nil, isDone: doneUIDs.contains(m.uid))
        }
        return (moodle + own).sorted { $0.due < $1.due }
    }

    /// Applies Moodle "submitted" reports: marks newly submitted deadlines done, never undoes anything.
    /// Each deadline is applied once, so unticking one by hand sticks.
    mutating func applySubmissions(_ ids: Set<Int>) {
        for d in deadlines() {
            guard let id = d.event.moodleEventID, ids.contains(id), !submittedIDs.contains(id) else { continue }
            submittedIDs.insert(id)
            if !d.isDone { setDone(d, true) }
        }
    }

    /// Moodle's export only looks back a few days, so keep earlier events from this semester:
    /// past homework stays linked to its cube and the class marker stays put.
    /// What changed in a feed refresh, for alerts.
    struct FeedChanges: Equatable {
        /// Upcoming deadlines that weren't in the feed before.
        var added: [MoodleEvent] = []
        /// Upcoming deadlines whose due time changed: (event, old due).
        var moved: [(event: MoodleEvent, from: Date)] = []
        static func == (a: Self, b: Self) -> Bool { a.added == b.added && a.moved.map(\.event) == b.moved.map(\.event) }
    }

    @discardableResult
    mutating func mergeFeed(_ fresh: [MoodleEvent], now: Date) -> FeedChanges {
        let old = Dictionary(events.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        var changes = FeedChanges()
        // The first sync has nothing to compare with: don't announce the whole semester.
        if !old.isEmpty {
            let ignored = ignoredCourseKeys
            for e in fresh where e.due > now && Classifier.isProblemSet(summary: e.summary, description: e.description)
                && !(e.courseKey.map(ignored.contains) ?? false) {
                if let o = old[e.uid] {
                    if abs(o.due.timeIntervalSince(e.due)) > 60 { changes.moved.append((e, o.due)) }
                } else {
                    changes.added.append(e)
                }
            }
        }
        let ids = Set(fresh.map(\.uid))
        let kept = events.filter { !ids.contains($0.uid) && $0.end < now && $0.end >= settings.semesterStart }
        events = (fresh + kept).sorted { $0.start < $1.start }
        return changes
    }

    /// Marks a deadline submitted (or not). Submitting also fills its homework cube; unticking leaves the cube alone.
    mutating func setDone(_ d: Deadline, _ done: Bool) {
        if done { doneUIDs.insert(d.id) } else { doneUIDs.remove(d.id) }
        if done, let ci = d.courseIndex, let c = d.cell, [.empty, .todo].contains(courses[ci].tracks[c.track].cells[c.index]) {
            courses[ci].tracks[c.track].cells[c.index] = .done
        }
    }
}

enum Pacing {
    /// How many sessions of this track the class has held by `now`.
    /// Homework uses Moodle due dates when linked; everything else is estimated from the weekly rate,
    /// plus the track's manual offset (for holidays and cancelled classes).
    static func classPosition(_ t: Track, links: [Int: MoodleEvent], settings s: Settings, now: Date) -> Int {
        let base: Int
        if t.kind == .homework, !links.isEmpty {
            // Last homework already due; if none is in the feed, the class is just before the first upcoming one.
            base = links.filter { $0.value.due <= now }.keys.max().map { $0 + 1 } ?? links.keys.min() ?? 0
        } else {
            base = sessions(perWeek: t.perWeek, from: s.semesterStart, to: min(now, s.semesterEnd))
        }
        return min(t.count, max(0, base + t.classOffset))
    }

    /// Sessions held between start and `to`, counting the first session on day one.
    static func sessions(perWeek: Int, from start: Date, to: Date) -> Int {
        guard to > start, perWeek > 0 else { return 0 }
        let weeks = to.timeIntervalSince(start) / (7 * 86400)
        return Int((weeks * Double(perWeek)).rounded(.up))
    }

    /// The furthest item you've got past (done / revisit / skipped).
    static func yourPosition(_ t: Track) -> Int {
        (t.cells.lastIndex { $0.isPassed } ?? -1) + 1
    }

    /// Where you should be: the class position, or for self-study a straight line to the target date.
    static func plannedPosition(_ t: Track, course: Course, classPos: Int, settings s: Settings, now: Date) -> Int {
        guard course.pace == .selfStudy else { return classPos }
        let target = course.targetDate ?? s.semesterEnd
        guard target > s.semesterStart else { return t.count }
        let f = min(1, max(0, now.timeIntervalSince(s.semesterStart) / target.timeIntervalSince(s.semesterStart)))
        return Int((f * Double(t.count)).rounded(.down))
    }

    /// Items before the planned position that are still open.
    static func behind(_ t: Track, planned: Int) -> Int {
        t.cells.prefix(planned).filter { $0 == .empty || $0 == .todo }.count
    }

    static func completion(_ c: Course) -> (done: Int, total: Int) {
        let cells = c.tracks.flatMap(\.cells).filter { $0 != .skipped }
        return (cells.filter { $0 == .done }.count, cells.count)
    }
}
