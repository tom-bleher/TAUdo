import Foundation

/// Same states and click-cycle order as the original track.html.
enum CellState: String, Codable, CaseIterable, Sendable {
    case empty = "", done, todo, revisit, skipped

    var next: CellState { let all = Self.allCases; return all[(all.firstIndex(of: self)! + 1) % all.count] }
    var label: String {
        switch self {
        case .empty: String(localized: "Not done")
        case .done: String(localized: "Done")
        case .todo: String(localized: "To do")
        case .revisit: String(localized: "Revisit")
        case .skipped: String(localized: "Skipped")
        }
    }
    /// Counts as "got past this item" when measuring how far you are.
    var isPassed: Bool { self == .done || self == .revisit || self == .skipped }

    /// Unknown values (e.g. from a newer version) read as not done instead of failing the whole file.
    init(from d: Decoder) throws { self = Self(rawValue: try d.singleValueContainer().decode(String.self)) ?? .empty }
}

enum TrackKind: String, Codable, CaseIterable, Sendable {
    case lecture, recitation, homework, other

    var label: String {
        switch self {
        case .lecture: String(localized: "Lecture")
        case .recitation: String(localized: "Recitation")
        case .homework: String(localized: "Homework")
        case .other: String(localized: "Other")
        }
    }

    init(from d: Decoder) throws { self = Self(rawValue: try d.singleValueContainer().decode(String.self)) ?? .other }
}

struct Track: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: TrackKind
    var cells: [CellState]
    /// Class sessions per week, used to estimate where the class is.
    var perWeek: Int
    /// Manual correction (holidays, cancelled classes) added to the computed class position.
    var classOffset: Int = 0

    init(name: String, kind: TrackKind, count: Int, perWeek: Int, cells: [CellState] = []) {
        self.name = name; self.kind = kind; self.perWeek = perWeek
        self.cells = Array((cells + Array(repeating: .empty, count: max(0, count - cells.count))).prefix(count))
    }

    /// Row label in the panel.
    var shortName: String {
        switch kind {
        case .lecture: String(localized: "Lec", comment: "Short row label for lectures")
        case .recitation: String(localized: "Rec", comment: "Short row label for recitations")
        case .homework: String(localized: "HW", comment: "Short row label for homework")
        case .other: String(name.prefix(4))
        }
    }

    var count: Int {
        get { cells.count }
        set { cells = Array((cells + Array(repeating: .empty, count: max(0, newValue - cells.count))).prefix(max(0, newValue))) }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(TrackKind.self, forKey: .kind) ?? .other
        cells = try c.decodeIfPresent([CellState].self, forKey: .cells) ?? []
        perWeek = try c.decodeIfPresent(Int.self, forKey: .perWeek) ?? 1
        classOffset = try c.decodeIfPresent(Int.self, forKey: .classOffset) ?? 0
    }
}

enum Pace: String, Codable, CaseIterable, Sendable {
    /// Follow the class; anything the class has covered that you haven't is "behind".
    case withClass
    /// Study at your own pace toward a target date; the class position is shown for reference.
    case selfStudy

    var label: String { self == .withClass ? String(localized: "With class") : String(localized: "Self-study") }

    init(from d: Decoder) throws { self = Self(rawValue: try d.singleValueContainer().decode(String.self)) ?? .withClass }
}

struct Course: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var pace: Pace = .withClass
    /// Moodle course shortname (the CATEGORIES value in the iCal export).
    var moodleKey: String?
    /// Self-study target: finish everything by this date (defaults to the semester end).
    var targetDate: Date?
    /// Course folder; defaults to <coursework folder>/<course name>.
    var folder: String?
    var tracks: [Track]

    init(name: String, pace: Pace = .withClass, tracks: [Track]) {
        self.name = name; self.pace = pace; self.tracks = tracks
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        pace = try c.decodeIfPresent(Pace.self, forKey: .pace) ?? .withClass
        moodleKey = try c.decodeIfPresent(String.self, forKey: .moodleKey)
        targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
    }

    /// Lecture / Recitation / Homework rows like track.html (25 / 13 / 13 for a 13-week TAU semester).
    /// Lecture / Recitation / Homework rows for a 13-week TAU semester (2 lectures a week).
    static func standard(_ name: String, pace: Pace = .withClass, lectures: String = "", recitations: String = "", homework: String = "", lectureCount: Int = 26) -> Course {
        Course(name: name, pace: pace, tracks: [
            Track(name: TrackKind.lecture.label, kind: .lecture, count: lectureCount, perWeek: 2, cells: seed(lectures)),
            Track(name: TrackKind.recitation.label, kind: .recitation, count: 13, perWeek: 1, cells: seed(recitations)),
            Track(name: TrackKind.homework.label, kind: .homework, count: 13, perWeek: 1, cells: seed(homework)),
        ])
    }

    /// track.html seed strings: d=done t=todo r=revisit s=skipped .=empty
    static func seed(_ s: String) -> [CellState] {
        s.map { ["d": .done, "t": .todo, "r": .revisit, "s": .skipped][$0] ?? .empty }
    }
}

struct Settings: Codable, Hashable, Sendable {
    var exportURL: String = ""
    /// The current academic year lives at the root; past years move to /<year>.
    var moodleBaseURL: String = "https://moodle.tau.ac.il"
    var semesterStart: Date = Settings.day(2026, 10, 18)
    var semesterEnd: Date = Settings.day(2027, 1, 17)
    var refreshMinutes: Int = 60
    var calendarSync: Bool = false
    var calendarName: String = "Moodle"
    var calendarID: String?
    /// Also put lectures/recitations/other Moodle events in the calendar, not just deadlines.
    var calendarIncludesAllEvents: Bool = true
    var notifications: Bool = true
    /// Minutes before a deadline to remind you (only while it's not done).
    var reminderMinutes: [Int] = [24 * 60, 3 * 60]
    /// Alert when Moodle posts a new deadline or moves one.
    var alertChanges: Bool = true
    /// Morning summary of today's and tomorrow's deadlines (hour of day; nil = off).
    var digestHour: Int? = 8
    /// Folder holding one subfolder per course (named like the course), for opening lecture videos, psets, …
    var courseworkFolder: String = ""
    /// Secret baked into the sync bookmark, so other web pages can't send taudo://sync data.
    var syncKey: String = UUID().uuidString
    /// List deadlines that have already passed (hidden by default).
    var showOverdue: Bool = false
    /// Show the next open deadline ("Calculus HW 4 · 2d") next to the menu bar icon.
    var menuBarShowsNext: Bool = true

    init() {}

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ICS.defaultTimeZone
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let z = Settings()
        exportURL = try c.decodeIfPresent(String.self, forKey: .exportURL) ?? z.exportURL
        moodleBaseURL = try c.decodeIfPresent(String.self, forKey: .moodleBaseURL) ?? z.moodleBaseURL
        semesterStart = try c.decodeIfPresent(Date.self, forKey: .semesterStart) ?? z.semesterStart
        semesterEnd = try c.decodeIfPresent(Date.self, forKey: .semesterEnd) ?? z.semesterEnd
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? z.refreshMinutes
        calendarSync = try c.decodeIfPresent(Bool.self, forKey: .calendarSync) ?? z.calendarSync
        calendarName = try c.decodeIfPresent(String.self, forKey: .calendarName) ?? z.calendarName
        calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
        calendarIncludesAllEvents = try c.decodeIfPresent(Bool.self, forKey: .calendarIncludesAllEvents) ?? z.calendarIncludesAllEvents
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? z.notifications
        reminderMinutes = try c.decodeIfPresent([Int].self, forKey: .reminderMinutes) ?? z.reminderMinutes
        alertChanges = try c.decodeIfPresent(Bool.self, forKey: .alertChanges) ?? z.alertChanges
        digestHour = c.contains(.digestHour) ? try c.decodeIfPresent(Int.self, forKey: .digestHour) : z.digestHour
        menuBarShowsNext = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsNext) ?? z.menuBarShowsNext
        showOverdue = try c.decodeIfPresent(Bool.self, forKey: .showOverdue) ?? z.showOverdue
        courseworkFolder = try c.decodeIfPresent(String.self, forKey: .courseworkFolder) ?? z.courseworkFolder
        syncKey = try c.decodeIfPresent(String.self, forKey: .syncKey) ?? z.syncKey
    }
}

extension AppData {
    /// The course's folder if it exists: its own setting, else <coursework folder>/<name>.
    func folder(for c: Course) -> URL? {
        let path = (c.folder?.isEmpty == false ? c.folder! : (settings.courseworkFolder as NSString).appendingPathComponent(c.name))
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    /// Display name for a Moodle course key: the linked course, else Moodle's full name, else the key.
    func courseLabel(_ key: String?) -> String {
        guard let key else { return String(localized: "Other") }
        return courses.first { $0.moodleKey == key }?.name ?? Self.readableName(moodleCourseNames[key] ?? key)
    }

    /// Significant words of a course name for matching: words of 3+ letters plus anything with a digit
    /// ("1", "1א"), so "Physics 1" and "Physics 2" stay different.
    static func nameWords(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { ($0.count > 2 || $0.contains(where: \.isNumber)) && !["for", "the", "and"].contains($0) })
    }

    /// The tracked course a Moodle course name belongs to: an exact link first, else the one course whose
    /// name's words all appear in it. nil if none or ambiguous.
    func course(matching moodleName: String) -> Int? {
        let readable = Self.readableName(moodleName)
        if let i = courses.firstIndex(where: { c in
            c.moodleKey.map { Self.readableName($0) == readable || Self.readableName(moodleCourseNames[$0] ?? "") == readable } ?? false
        }) { return i }
        let target = Self.nameWords(moodleName)
        let hits = courses.indices.filter { let w = Self.nameWords(courses[$0].name); return !w.isEmpty && w.isSubset(of: target) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// TAU course names look like "0321213001 - שיטות בפיזיקה עיונית 1" or "Hebrew name - English name":
    /// drop the leading course code, and prefer the English part when there is one.
    static func readableName(_ full: String) -> String {
        let parts = full.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
        guard !parts.isEmpty else { return full }
        return parts.last(where: { $0.contains { $0.isASCII && $0.isLetter } }) ?? parts.joined(separator: " - ")
    }
}

/// An exam or deadline you add yourself.
struct ManualDeadline: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var due: Date
    var courseID: UUID?

    var uid: String { "manual-\(id.uuidString)" }
}

/// Everything persisted to ~/Library/Application Support/TAUdo/state.json.
struct AppData: Codable, Sendable {
    var courses: [Course]
    var settings = Settings()
    /// Last successfully fetched Moodle feed (kept so the app works offline).
    var events: [MoodleEvent] = []
    var lastSync: Date?
    /// Exam dates from Arazim, and when they were last fetched.
    var exams: [MoodleEvent] = []
    var examsFetched: Date?
    /// Deadlines you submitted (ticked, or reported by Moodle).
    var doneUIDs: Set<String> = []
    /// Moodle event IDs Moodle reported as submitted (only ever upgrades a cube to done).
    var submittedIDs: Set<Int> = []
    /// Deadlines hidden from the list (e.g. not actually yours to do).
    var hiddenUIDs: Set<String> = []
    var manual: [ManualDeadline] = []
    /// Moodle courses you said aren't yours: their deadlines are ignored.
    var ignoredCourseKeys: Set<String> = []
    /// Finished the welcome window.
    var onboarded = false
    /// Course downloads whose files may still arrive in ~/Downloads.
    var downloads: [DownloadManifest] = []
    /// Moodle course shortname → full name (sent by the sync bookmark).
    var moodleCourseNames: [String: String] = [:]
    /// Last time the TAUdo sync bookmarklet reported submission status.
    var lastStatusCheck: Date?

    init(courses: [Course]) { self.courses = courses }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        events = try c.decodeIfPresent([MoodleEvent].self, forKey: .events) ?? []
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        exams = try c.decodeIfPresent([MoodleEvent].self, forKey: .exams) ?? []
        examsFetched = try c.decodeIfPresent(Date.self, forKey: .examsFetched)
        doneUIDs = try c.decodeIfPresent(Set<String>.self, forKey: .doneUIDs) ?? []
        submittedIDs = try c.decodeIfPresent(Set<Int>.self, forKey: .submittedIDs) ?? []
        hiddenUIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenUIDs) ?? []
        manual = try c.decodeIfPresent([ManualDeadline].self, forKey: .manual) ?? []
        ignoredCourseKeys = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredCourseKeys) ?? []
        downloads = try c.decodeIfPresent([DownloadManifest].self, forKey: .downloads) ?? []
        // States from before the welcome window existed already have courses: don't onboard them again.
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? !courses.isEmpty
        lastStatusCheck = try c.decodeIfPresent(Date.self, forKey: .lastStatusCheck)
        moodleCourseNames = try c.decodeIfPresent([String: String].self, forKey: .moodleCourseNames) ?? [:]
    }

    /// A fresh install starts empty; the welcome window creates courses from Moodle.
    static var initial: AppData { AppData(courses: []) }
}

extension AppData {
    /// Imports `localStorage["course-tracker-v1"]` from track.html: [{name, rows:[[state]]}] (or the old {weeks}).
    static func importTrackHTML(_ json: String) throws -> [Course] {
        struct Legacy: Decodable { var name: String; var rows: [[String]]? ; var weeks: [[String]]? }
        let legacy = try JSONDecoder().decode([Legacy].self, from: Data(json.utf8))
        let names = ["Lecture", "Recitation", "Homework"], kinds: [TrackKind] = [.lecture, .recitation, .homework]
        let counts = [25, 13, 13], perWeek = [2, 1, 1]
        return legacy.map { l in
            let rows: [[String]] = l.rows ?? (0..<3).map { k in (l.weeks ?? []).map { $0.indices.contains(k) ? $0[k] : "" } }
            let tracks = (0..<max(3, rows.count)).map { k in
                let cells = (rows.indices.contains(k) ? rows[k] : []).map { CellState(rawValue: $0) ?? .empty }
                return k < 3 ? Track(name: names[k], kind: kinds[k], count: max(counts[k], cells.count), perWeek: perWeek[k], cells: cells)
                             : Track(name: "Row \(k + 1)", kind: .other, count: cells.count, perWeek: 1, cells: cells)
            }
            return Course(name: l.name, tracks: tracks)
        }
    }
}
