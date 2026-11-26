import JavaScriptCore
import XCTest

final class ICSTests: XCTestCase {
    let sample = [
        "BEGIN:VCALENDAR", "PRODID:-//Moodle Pty Ltd//NONSGML Moodle Version 2024100700//EN",
        "BEGIN:VEVENT", "UID:4242@moodle.tau.ac.il",
        "SUMMARY:תרגיל בית 3 - טורי פורייה\\, חלק א is due",
        "DESCRIPTION:הגשה ב-PDF\\nראו https://moodle.tau.ac.il/2026/mod/assign/view.php?id=77 לפ",
        " רטים",
        "CLASS:PUBLIC", "LAST-MODIFIED:20261101T100000Z",
        "DTSTART:20261125T215900Z", "DTEND:20261125T215900Z",
        "CATEGORIES:0321-2113-01",
        "BEGIN:VALARM", "TRIGGER:-PT15M", "DESCRIPTION:ignore me", "END:VALARM",
        "END:VEVENT",
        "BEGIN:VEVENT", "UID:4243@moodle.tau.ac.il", "SUMMARY:תרגול 4",
        "DTSTART;TZID=Asia/Jerusalem:20261126T140000", "DTEND;TZID=Asia/Jerusalem:20261126T150000",
        "END:VEVENT",
        "BEGIN:VEVENT", "UID:4244@moodle.tau.ac.il", "SUMMARY:Holiday", "DTSTART;VALUE=DATE:20261201", "END:VEVENT",
        "BEGIN:VEVENT", "SUMMARY:no uid, dropped", "DTSTART:20261201T000000Z", "END:VEVENT",
        "END:VCALENDAR",
    ].joined(separator: "\r\n")

    func testParse() throws {
        let ev = ICS.parse(sample)
        XCTAssertEqual(ev.count, 3)
        let hw = ev[0]
        XCTAssertEqual(hw.summary, "תרגיל בית 3 - טורי פורייה, חלק א is due")
        XCTAssertEqual(hw.courseKey, "0321-2113-01")
        XCTAssertEqual(hw.moodleEventID, 4242)
        XCTAssertTrue(hw.description.hasSuffix("לפרטים"), "folded line joined")
        XCTAssertTrue(hw.description.contains("\n"))
        XCTAssertEqual(hw.url, "https://moodle.tau.ac.il/2026/mod/assign/view.php?id=77")
        XCTAssertEqual(hw.due, ISO8601DateFormatter().date(from: "2026-11-25T21:59:00Z"))
        // Israel is UTC+2 in November.
        XCTAssertEqual(ev[1].start, ISO8601DateFormatter().date(from: "2026-11-26T12:00:00Z"))
        XCTAssertTrue(ev[2].isAllDay)
    }
}

final class ClassifierTests: XCTestCase {
    func testProblemSets() {
        for s in ["תרגיל בית 3 is due", "Problem Set 4 is due", "HW 2", "מטלה 1", "בוחן אמצע", "Exam A", "מבחן מועד א"] {
            XCTAssertTrue(Classifier.isProblemSet(summary: s), s)
        }
        for s in ["תרגול 4", "הרצאה 12", "Lecture 3", "Zoom office hours"] {
            XCTAssertFalse(Classifier.isProblemSet(summary: s), s)
        }
    }

    func testNumbers() {
        XCTAssertEqual(Classifier.assignmentNumber("תרגיל בית 3 - טורי פורייה is due"), 3)
        XCTAssertEqual(Classifier.assignmentNumber("תרגיל מס' 12"), 12)
        XCTAssertEqual(Classifier.assignmentNumber("Problem Set 05 is due"), 5)
        XCTAssertEqual(Classifier.assignmentNumber("HW #4"), 4)
        XCTAssertEqual(Classifier.assignmentNumber("גיליון 2"), 2)
        XCTAssertNil(Classifier.assignmentNumber("תרגול 4"))
        XCTAssertNil(Classifier.assignmentNumber("Exam 2026"))
    }

    func testCleanTitle() {
        XCTAssertEqual(Classifier.cleanTitle("Problem Set 4 is due"), "Problem Set 4")
        XCTAssertEqual(Classifier.cleanTitle("תרגיל 2 - יש להגיש"), "תרגיל 2")
        XCTAssertTrue(Classifier.isExam("בוחן אמצע") == false && Classifier.isExam("מבחן מועד א"))
    }
}

final class ProgressTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z")!

    func testDeadlinesLinkToCubes() {
        let d = Demo.data(now: now)
        let dl = d.deadlines()
        // Methods (course 0) HW 7 was seeded "t" (to do) → linked, not done; HW 8 linked too.
        let hw7 = dl.first { $0.title == "תרגיל בית 7" }!
        XCTAssertEqual(hw7.courseIndex, 0)
        XCTAssertEqual(hw7.cell?.index, 6)
        XCTAssertFalse(hw7.isDone)
        XCTAssertFalse(dl.contains { $0.title.hasPrefix("הרצאה") }, "lectures aren't deadlines")
        XCTAssertTrue(dl.contains { $0.isManual && $0.title == "מבחן אמצע" })
        XCTAssertEqual(dl.map(\.due), dl.map(\.due).sorted())
    }

    func testSubmissionsApplyOnce() {
        var d = Demo.data(now: now)
        d.applySubmissions([9002])   // Methods HW 8
        XCTAssertEqual(d.courses[0].tracks[2].cells[7], .done)
        XCTAssertTrue(d.deadlines().first { $0.event.moodleEventID == 9002 }!.isDone)
        // Untick by hand; the same report must not re-tick it. The cube keeps its state.
        d.setDone(d.deadlines().first { $0.event.moodleEventID == 9002 }!, false)
        d.applySubmissions([9002])
        XCTAssertFalse(d.deadlines().first { $0.event.moodleEventID == 9002 }!.isDone)
        XCTAssertEqual(d.courses[0].tracks[2].cells[7], .done)
        // An exam has no cube: it is tracked by UID instead.
        d.applySubmissions([9006])
        XCTAssertTrue(d.doneUIDs.contains("9006@moodle.tau.ac.il"))
    }

    func testClassPosition() {
        var s = Settings()
        s.semesterStart = Settings.day(2026, 10, 18)
        let lec = Track(name: "Lecture", kind: .lecture, count: 25, perWeek: 2)
        // 5 weeks + ~2.4 days after start → ceil(5.35 * 2) = 11 lectures held.
        XCTAssertEqual(Pacing.classPosition(lec, links: [:], settings: s, now: s.semesterStart.addingTimeInterval((35 + 2.4) * 86400)), 11)
        var shifted = lec; shifted.classOffset = -2
        XCTAssertEqual(Pacing.classPosition(shifted, links: [:], settings: s, now: s.semesterStart.addingTimeInterval((35 + 2.4) * 86400)), 9)
        XCTAssertEqual(Pacing.classPosition(lec, links: [:], settings: s, now: s.semesterStart.addingTimeInterval(-86400)), 0)
        XCTAssertEqual(Pacing.classPosition(lec, links: [:], settings: s, now: Settings.day(2027, 6, 1)), 25)

        let hw = Track(name: "Homework", kind: .homework, count: 13, perWeek: 1)
        let e = { (days: Double) in MoodleEvent(uid: "x", summary: "", start: self.now.addingTimeInterval(days * 86400), end: self.now.addingTimeInterval(days * 86400)) }
        XCTAssertEqual(Pacing.classPosition(hw, links: [0: e(-10), 1: e(-3), 2: e(4)], settings: s, now: now), 2)
    }

    func testYouVsClass() {
        let t = Track(name: "L", kind: .lecture, count: 10, perWeek: 2, cells: Course.seed("ddd.r..s"))
        XCTAssertEqual(Pacing.yourPosition(t), 8)
        var c = Course(name: "c", pace: .selfStudy, tracks: [t])
        var s = Settings()
        s.semesterStart = Settings.day(2026, 10, 1)
        c.targetDate = Settings.day(2026, 10, 11)
        XCTAssertEqual(Pacing.plannedPosition(t, course: c, classPos: 3, settings: s, now: Settings.day(2026, 10, 6)), 3, "self-study off")
        s.selfStudy = true
        XCTAssertEqual(Pacing.plannedPosition(t, course: c, classPos: 3, settings: s, now: Settings.day(2026, 10, 6)), 5)
        c.pace = .withClass
        XCTAssertEqual(Pacing.plannedPosition(t, course: c, classPos: 3, settings: s, now: Settings.day(2026, 10, 6)), 3)
    }

    func testSelfStudySettingMigrates() throws {
        let raw = { (pace: String, setting: String) in
            Data(#"{"settings":{\#(setting)},"courses":[{"name":"X","pace":"\#(pace)","tracks":[]}]}"#.utf8)
        }
        XCTAssertTrue(try JSONDecoder().decode(AppData.self, from: raw("selfStudy", "")).settings.selfStudy, "already in use: stays on")
        XCTAssertFalse(try JSONDecoder().decode(AppData.self, from: raw("withClass", "")).settings.selfStudy)
        XCTAssertFalse(try JSONDecoder().decode(AppData.self, from: raw("selfStudy", #""selfStudy":false"#)).settings.selfStudy, "explicit off wins")
    }
}

final class PersistenceTests: XCTestCase {
    /// The semester's end follows its start into another semester, and is 13 weeks on even across daylight saving.
    func testSemesterEndFollowsStart() throws {
        var s = Settings()
        s.semesterStart = Settings.day(2026, 10, 18); s.semesterEnd = Settings.day(2027, 1, 17)
        s.fitSemesterEnd()
        XCTAssertEqual(s.semesterEnd, Settings.day(2027, 1, 17), "within the semester: kept")
        s.semesterStart = Settings.day(2027, 3, 14)
        s.fitSemesterEnd()
        XCTAssertEqual(s.semesterEnd, Settings.day(2027, 6, 13), "start moved past the end")
        s.semesterStart = Settings.day(2026, 10, 18)
        s.fitSemesterEnd()
        XCTAssertEqual(s.semesterEnd, Settings.day(2027, 1, 17), "start moved far back")
        let raw = #"{"semesterStart":"2027-03-13T22:00:00Z","semesterEnd":"2027-01-16T22:00:00Z"}"#
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(Settings.self, from: Data(raw.utf8)).semesterEnd, Settings.day(2027, 6, 13), "saved end before start")
    }

    func testDecodesOldOrPartialState() throws {
        let raw = #"{"courses":[{"name":"X","tracks":[{"name":"Lecture","cells":["done"]}]}],"settings":{"exportURL":"u"}}"#
        let d = try JSONDecoder().decode(AppData.self, from: Data(raw.utf8))
        XCTAssertEqual(d.settings.exportURL, "u")
        XCTAssertEqual(d.settings.refreshMinutes, 60)
        XCTAssertEqual(d.courses[0].tracks[0].perWeek, 1)
        XCTAssertTrue(d.events.isEmpty)
    }

    func testRoundTrip() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let d = Demo.data(now: Date(timeIntervalSince1970: 1_800_000_000))
        let back = try dec.decode(AppData.self, from: enc.encode(d))
        XCTAssertEqual(back.courses, d.courses)
        XCTAssertEqual(back.events, d.events)
        XCTAssertEqual(back.manual, d.manual)
    }
}

final class ConnectTests: XCTestCase {
    let host = "moodle.tau.ac.il"

    func testExportLink() {
        let good = "webcal://moodle.tau.ac.il/calendar/export_execute.php?userid=4711&authtoken=abc"
        XCTAssertEqual(MoodleConnect.exportLink(good, host: host),
                       "https://moodle.tau.ac.il/calendar/export_execute.php?userid=4711&authtoken=abc&preset_what=all&preset_time=custom")
        XCTAssertNil(MoodleConnect.exportLink("https://moodle.tau.ac.il/calendar/export_execute.php?userid=1&authtoken=abc", host: host), "guest")
        XCTAssertNil(MoodleConnect.exportLink("https://evil.example/calendar/export_execute.php?userid=5&authtoken=abc", host: host))
        XCTAssertNil(MoodleConnect.exportLink("https://moodle.tau.ac.il/my/", host: host))
    }

    func testPayload() throws {
        let json = #"{"key":"k","base":"https://moodle.tau.ac.il","exportURL":null,"v":4,"submitted":[1,3],"courses":{"0321-1":"Physics"}}"#
        var c = URLComponents(string: "taudo://sync")!
        c.queryItems = [URLQueryItem(name: "d", value: json)]
        let p = try XCTUnwrap(MoodleConnect.payload(from: c.url!))
        XCTAssertEqual(p.submitted, [1, 3])
        XCTAssertEqual(p.key, "k")
        XCTAssertEqual(p.courses?["0321-1"], "Physics")
        XCTAssertNil(MoodleConnect.payload(from: URL(string: "taudo://other?d=x")!))
    }

    /// Deadlines open their Moodle page: the activity the bookmark linked, else Moodle's calendar on that day.
    func testMoodleLinks() throws {
        var c = URLComponents(string: "taudo://sync")!
        c.queryItems = [URLQueryItem(name: "d", value: #"{"base":"x","v":4,"links":{"#
            + #""9448":"https://moodle.tau.ac.il/mod/assign/view.php?id=77","1":"https://evil.example/mod/x","#
            + #""2":"https://moodle.tau.ac.il/login/logout.php","x":"https://moodle.tau.ac.il/mod/quiz/view.php?id=1"}}"#)]
        let p = try XCTUnwrap(MoodleConnect.payload(from: c.url!))
        XCTAssertEqual(p.validLinks(host: "moodle.tau.ac.il"), ["9448": "https://moodle.tau.ac.il/mod/assign/view.php?id=77"])

        var d = AppData(courses: [])
        d.moodleLinks = p.validLinks(host: "moodle.tau.ac.il")
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let ev = { (uid: String) in MoodleEvent(uid: uid, summary: "HW", start: at, end: at) }
        XCTAssertEqual(d.moodleURL(for: ev("9448@moodle.tau.ac.il"))?.absoluteString, "https://moodle.tau.ac.il/mod/assign/view.php?id=77")
        XCTAssertEqual(d.moodleURL(for: ev("9449@moodle.tau.ac.il"))?.absoluteString,
                       "https://moodle.tau.ac.il/calendar/view.php?view=day&time=1800000000#event_9449")
        XCTAssertNil(d.moodleURL(for: ev("arazim-1-א-2027-01-01")))
        XCTAssertNil(d.moodleURL(for: ev("manual-x")))
    }

    /// Bookmarks before version 4 inferred "submitted" from Moodle's to-do list, which also drops assignments whose
    /// completion condition (e.g. "view") is met: their reports are ignored.
    func testOldBookmarksReportNoSubmissions() throws {
        var c = URLComponents(string: "taudo://sync")!
        c.queryItems = [URLQueryItem(name: "d", value: #"{"base":"x","v":3,"pendingIDs":[2],"pendingFrom":1000000}"#)]
        XCTAssertNil(try XCTUnwrap(MoodleConnect.payload(from: c.url!)).submitted)
    }

    func testBookmarkletIsValidJavaScript() throws {
        // Decodes the javascript: URL and syntax-checks it with JavaScriptCore.
        let code = try XCTUnwrap(MoodleConnect.bookmarkletURL(key: "k", base: "https://moodle.tau.ac.il/").dropFirst("javascript:".count).removingPercentEncoding)
        XCTAssertTrue(code.contains(#"if (location.origin !== "https:\/\/moodle.tau.ac.il")"#), "only runs on your Moodle")
        XCTAssertNil(code.range(of: #"__[A-Z0-9]+__"#, options: .regularExpression), "every placeholder is filled in")
        let ctx = try XCTUnwrap(JSContext())
        var error: String?
        ctx.exceptionHandler = { _, e in error = e?.toString() }
        ctx.evaluateScript("new Function(\(String(data: try JSONEncoder().encode(code), encoding: .utf8)!))")
        XCTAssertNil(error)
    }
}

final class CourseFilesTests: XCTestCase {
    func testNumbers() {
        XCTAssertEqual(CourseFiles.number("שיעור 03"), 3)
        XCTAssertEqual(CourseFiles.number("01 - 0366110001 - Calculus 1a for Physics"), 1)
        XCTAssertEqual(CourseFiles.number("pset10"), 10)
        XCTAssertEqual(CourseFiles.number("rec3"), 3)
        XCTAssertNil(CourseFiles.number("LinAlg"))
    }

    func testScanAndLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        func touch(_ p: String) throws {
            let u = root.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: u.path, contents: Data())
        }
        try touch("psets/pset7/07-Homework.pdf")
        try touch("psets/pset10/pset10.lyx")
        try touch("videos/bar-sinai/03 - 0366110001 - Calculus 1a for Physics.mkv")
        try touch("videos/bar-sinai/lecture_notes/03.pdf")
        try touch("videos/שיעור 04.mp4")
        try touch("recitations/rec2.pdf")
        try touch("_to_delete/psets/pset1/x.pdf")
        let f = CourseFiles.scan(root)
        XCTAssertEqual(f.urls(.homework, 7).map(\.lastPathComponent), ["pset7"])
        XCTAssertEqual(f.urls(.homework, 10).count, 1)
        XCTAssertTrue(f.urls(.homework, 1).isEmpty, "_to_delete is skipped")
        XCTAssertNil(f.items[.lecture], "recordings open on Panopto, not from disk")
        XCTAssertEqual(f.urls(.recitation, 2).count, 1)
        XCTAssertTrue(f.codes.contains("0366110001"))

        var d = AppData(courses: [.standard("Calculus for Physics"), .standard("Linear Algebra for Physics"), .standard("Methods in Theoretical Physics 1")])
        let ev = { (key: String) in MoodleEvent(uid: key, summary: "HW 1", categories: [key], start: .now, end: .now) }
        d.events = [ev("0366-1100-01"), ev("0321-1112-01"), ev("9999")]
        d.moodleCourseNames = ["0321-1112-01": "אלגברה לינארית לפיזיקה - Linear Algebra 1 for Physics", "9999": "Physics Lab"]
        d.autoLinkCourses(files: [d.courses[0].id: f])
        XCTAssertEqual(d.courses[0].moodleKey, "0366-1100-01", "by course code in the course's files")
        XCTAssertEqual(d.courses[1].moodleKey, "0321-1112-01", "by name")
        XCTAssertNil(d.courses[2].moodleKey, "no match → stays unlinked")
    }
}

final class NamingTests: XCTestCase {
    func testReadableName() {
        XCTAssertEqual(AppData.readableName("מעבדה בפיזיקה 1 - Physics Lab 1"), "Physics Lab 1")
        XCTAssertEqual(AppData.readableName("חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה0366110001 - Calculus 1a for Physics"), "Calculus 1a for Physics")
        XCTAssertEqual(AppData.readableName("מכניקה אנליטית"), "מכניקה אנליטית")
    }
}

final class ReviewFixTests: XCTestCase {
    func testClassifierEdgeCases() {
        XCTAssertFalse(Classifier.isExam("מועד אחרון להגשת תרגיל 3"))
        XCTAssertTrue(Classifier.isExam("מבחן מועד א'"))
        XCTAssertFalse(Classifier.isExam("יש להגיש את 'תרגיל 3 מועד ב'"), "an assignment, though it names a sitting")
        XCTAssertFalse(Classifier.isExam("Practice exam is due"))
        XCTAssertTrue(Classifier.isProblemSet(summary: "Practice exam is due"))
        XCTAssertTrue(Classifier.isExam("Midterm"))
        XCTAssertFalse(Classifier.isExam("HW 5 final version"))
        XCTAssertFalse(Classifier.isProblemSet(summary: "Quiz 3 opens"))
        XCTAssertFalse(Classifier.isProblemSet(summary: "בוחן 3 נפתח"))
        XCTAssertTrue(Classifier.isProblemSet(summary: "Quiz 3 closes"))
    }

    func testMergeKeepsPastEvents() {
        let now = Settings.day(2026, 11, 24)
        var d = AppData(courses: [])
        let e = { (uid: String, day: Int) in MoodleEvent(uid: uid, summary: "HW", start: Settings.day(2026, 11, day), end: Settings.day(2026, 11, day)) }
        d.events = [e("old", 2), e("gone-future", 30), e("updated", 10)]
        d.mergeFeed([e("updated", 26), e("new", 28)], now: now)
        XCTAssertEqual(Set(d.events.map(\.uid)), ["old", "updated", "new"], "past kept, future that left the feed dropped")
        XCTAssertEqual(d.events.first { $0.uid == "updated" }?.end, Settings.day(2026, 11, 26), "feed wins")
    }

    func testHomeworkMarkerWithOnlyFutureLinks() {
        let now = Settings.day(2026, 11, 24)
        let hw = Track(name: "HW", kind: .homework, count: 13, perWeek: 1)
        let e = MoodleEvent(uid: "x", summary: "", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(86400))
        XCTAssertEqual(Pacing.classPosition(hw, links: [7: e, 8: e], settings: Settings(), now: now), 7)
    }

    func testUnknownStatesDecode() throws {
        let raw = #"{"courses":[{"name":"X","pace":"turbo","tracks":[{"name":"L","kind":"lab","cells":["done","future-state"]}]}]}"#
        let d = try JSONDecoder().decode(AppData.self, from: Data(raw.utf8))
        XCTAssertEqual(d.courses[0].tracks[0].cells, [.done, .empty])
        XCTAssertEqual(d.courses[0].tracks[0].kind, .other)
        XCTAssertEqual(d.courses[0].pace, .withClass)
    }
}

/// Title shapes seen in the real TAU Moodle (Hebrew interface) export.
final class RealMoodleTitleTests: XCTestCase {
    func testHebrewMoodleTitles() {
        let due = "יש להגיש את 'תרגיל בית 3'"
        XCTAssertTrue(Classifier.isProblemSet(summary: due))
        XCTAssertEqual(Classifier.cleanTitle(due), "תרגיל בית 3")
        XCTAssertEqual(Classifier.assignmentNumber(due), 3)

        let hw = "יש להגיש את 'הגשת שיעורי בית 4'"
        XCTAssertEqual(Classifier.cleanTitle(hw), "הגשת שיעורי בית 4")
        XCTAssertEqual(Classifier.assignmentNumber(hw), 4)

        XCTAssertEqual(Classifier.assignmentNumber("יש להגיש את 'תרגיל בית 4 - קבוצה 4'"), 4)

        let quizDue = "תאריך הגשה בוחן חזרה אופציונלי"
        XCTAssertTrue(Classifier.isProblemSet(summary: quizDue))
        XCTAssertEqual(Classifier.cleanTitle(quizDue), "בוחן חזרה אופציונלי")

        XCTAssertFalse(Classifier.isProblemSet(summary: "נפתח ב בוחן חזרה אופציונלי"), "an opening, not a deadline")
    }

    func testCourseKeyLabels() {
        XCTAssertEqual(AppData.readableName("0321213001 - שיטות בפיזיקה עיונית 1"), "שיטות בפיזיקה עיונית 1")
        XCTAssertEqual(AppData.readableName("0366110001 - חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה"), "חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה")
    }
}

final class OverdueSettingTests: XCTestCase {
    func testHiddenByDefault() {
        XCTAssertFalse(Settings().showOverdue)
        let d = try! JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertFalse(d.showOverdue)
    }

    /// The menu bar switch from before 0.3 carries over: off meant the icon alone.
    func testMenuBarSwitchMigrates() throws {
        let decode = { try JSONDecoder().decode(Settings.self, from: Data(($0 as String).utf8)) }
        XCTAssertEqual(try decode("{}").menuBar, .deadline)
        XCTAssertEqual(try decode(#"{"menuBarShowsNext": false}"#).menuBar, .icon)
        XCTAssertEqual(try decode(#"{"menuBarShowsNext": true}"#).menuBar, .deadline)
        XCTAssertEqual(try decode(#"{"menuBarShowsNext": false, "menuBar": "timeLeft"}"#).menuBar, .timeLeft)
        var s = Settings(); s.menuBar = .timeLeft; s.listLimit = 12; s.fetchExams = false
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)), s)
    }
}

final class ExamTabTests: XCTestCase {
    /// Exams live in their own tab; under Deadlines and in the menu bar only when asked for.
    func testExamsKeptOutOfDueUnlessAsked() {
        var d = AppData(courses: [])
        let now = Settings.day(2026, 11, 24)
        d.exams = [MoodleEvent(uid: "arazim-1", summary: "בחינה מועד א", start: now + 86400, end: now + 86400)]
        d.events = [MoodleEvent(uid: "hw", summary: "יש להגיש את 'תרגיל בית 1'", start: now + 2 * 86400, end: now + 2 * 86400)]
        XCTAssertEqual(d.deadlines().map(\.id), ["arazim-1", "hw"], "reminders and calendar still get exams")
        XCTAssertEqual(d.dueDeadlines().map(\.id), ["hw"])
        d.settings.examsWithDeadlines = true
        XCTAssertEqual(d.dueDeadlines().map(\.id), ["arazim-1", "hw"])
    }

    /// A Moodle exam with a length is due when it starts; anything else when it ends.
    func testTimedExamIsDueAtItsStart() {
        let at = Settings.day(2026, 12, 10) + 14 * 3600
        XCTAssertEqual(MoodleEvent(uid: "1", summary: "מבחן אמצע", start: at, end: at + 7200).due, at)
        XCTAssertEqual(MoodleEvent(uid: "2", summary: "תאריך הגשה בוחן 3", start: at, end: at + 7200).due, at + 7200)
        XCTAssertEqual(MoodleEvent(uid: "3", summary: "בחינה מועד א", start: at, end: at + 86399, isAllDay: true).due, at + 86399)
    }

    /// Arazim lists midterms in a special sitting ("מ"), whose title names no exam the classifier knows.
    func testEveryArazimEventIsAnExam() throws {
        let catalog = #"{"03211100": {"exams": [{"moed": "מ", "date": "14/05/2027", "hour": "09:00", "type": "בחינת ביניים"}]}}"#
        var d = AppData(courses: [])
        d.exams = try Arazim.exams(catalog: Data(catalog.utf8), moodleKeys: ["0321110001 - Algebra"])
        XCTAssertEqual(d.exams.map(\.summary), ["בחינת ביניים מועד מ"])
        XCTAssertEqual(d.deadlines().map(\.isExam), [true])
        XCTAssertEqual(d.dueDeadlines(), [])
    }
}

final class SubmittedVsSolvedTests: XCTestCase {
    func testDoneCubeDoesNotHideDeadline() {
        let now = Settings.day(2026, 11, 24)
        var d = Demo.data(now: now)
        // Methods HW 6 is done in the seed (studied ahead); this year's HW 6 deadline must still show.
        d.events.append(MoodleEvent(uid: "hw6", summary: "יש להגיש את 'תרגיל בית 6'", categories: [d.courses[0].moodleKey!], start: now + 86400, end: now + 86400))
        let hw6 = d.deadlines().first { $0.id == "hw6" }!
        XCTAssertEqual(hw6.cell?.index, 5)
        XCTAssertFalse(hw6.isDone)
    }
}

final class AlertTests: XCTestCase {
    let now = Settings.day(2026, 11, 24).addingTimeInterval(9 * 3600)
    func ev(_ uid: String, _ title: String, days: Double, key: String = "K") -> MoodleEvent {
        MoodleEvent(uid: uid, summary: title, categories: [key], start: now + days * 86400, end: now + days * 86400)
    }

    func testFeedChanges() {
        var d = AppData(courses: [])
        XCTAssertEqual(d.mergeFeed([ev("a", "HW 1", days: 2)], now: now), .init(), "first sync announces nothing")
        let c = d.mergeFeed([ev("a", "HW 1", days: 3), ev("b", "HW 2", days: 5), ev("lec", "Lecture 4", days: 1),
                             ev("ign", "HW 9", days: 2, key: "X")], now: now)
        XCTAssertEqual(c.moved.map(\.event.uid), ["a"])
        XCTAssertEqual(c.added.map(\.uid).sorted(), ["b", "ign"])
        d.ignoredCourseKeys = ["X"]
        let c2 = d.mergeFeed([ev("a", "HW 1", days: 3), ev("b", "HW 2", days: 5), ev("new-ign", "HW 10", days: 4, key: "X")], now: now)
        XCTAssertTrue(c2.added.isEmpty && c2.moved.isEmpty, "ignored courses and unchanged deadlines stay quiet")
    }

    func testDigest() {
        let mk = { (title: String, hours: Double, done: Bool) in
            Deadline(event: MoodleEvent(uid: title, summary: title, start: self.now + hours * 3600, end: self.now + hours * 3600), courseIndex: nil, cell: nil, isDone: done)
        }
        let list = [mk("today-open", 5, false), mk("tomorrow-open", 30, false), mk("today-done", 6, true), mk("later", 80, false)]
        let t = Digest.text(list, morning: now, courseName: { _ in "Course" })
        XCTAssertNotNil(t)
        XCTAssertTrue(t!.body.contains("today-open") && t!.body.contains("tomorrow-open"))
        XCTAssertFalse(t!.body.contains("today-done"), "done deadlines are left out")
        XCTAssertFalse(t!.body.contains("later"), "only today and tomorrow")
        XCTAssertNil(Digest.text([mk("later", 80, false)], morning: now, courseName: { _ in "" }))
    }
}

final class DownloadTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(DownloadOrganizer.parse("TAUdo__123__4__הרצאה 3.pdf"), .init(courseID: 123, section: "4", name: "הרצאה 3.pdf"))
        XCTAssertEqual(DownloadOrganizer.parse("TAUdo__123__all__course.zip")?.section, "all")
        XCTAssertEqual(DownloadOrganizer.parse("TAUdo__9__0__a__b.pdf")?.name, "a__b.pdf")
        XCTAssertNil(DownloadOrganizer.parse("TAUdo__123__4__file.pdf.crdownload"), "still downloading")
        XCTAssertNil(DownloadOrganizer.parse("lecture.pdf"))
        XCTAssertNil(DownloadOrganizer.parse("TAUdo__x__4__file.pdf"))
    }

    func testMover() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads"), course = root.appendingPathComponent("Course")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String = "x") throws { try Data(text.utf8).write(to: downloads.appendingPathComponent(name)) }
        try write("TAUdo__7__1__notes.pdf")
        try write("TAUdo__7__2__notes.pdf", "different")
        try write("TAUdo__8__1__other-course.pdf")
        try write("TAUdo__7__1__big.pdf.crdownload")
        try write("unrelated.pdf")
        // A folder zip, as Moodle's download_folder.php sends it.
        let staging = root.appendingPathComponent("stage/Problem sets")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("q".utf8).write(to: staging.appendingPathComponent("ps1.pdf"))
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", staging.path, downloads.appendingPathComponent("TAUdo__7__2__Problem sets.zip").path]
        try zip.run(); zip.waitUntilExit()

        let m = DownloadManifest(courseID: 7, name: "Course", sections: ["1": "Week 1: intro", "2": "שבוע 2"], count: 3)
        let moved = DownloadMover.run([(m, course)], downloads: downloads, now: Date().addingTimeInterval(10))
        XCTAssertEqual(moved[7], 3)
        XCTAssertTrue(fm.fileExists(atPath: course.appendingPathComponent("Moodle/01 Week 1- intro/notes.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: course.appendingPathComponent("Moodle/02 שבוע 2/notes.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: course.appendingPathComponent("Moodle/02 שבוע 2/Problem sets/ps1.pdf").path), "zip unpacked")
        XCTAssertTrue(fm.fileExists(atPath: downloads.appendingPathComponent("TAUdo__8__1__other-course.pdf").path), "unknown course left alone")
        XCTAssertTrue(fm.fileExists(atPath: downloads.appendingPathComponent("unrelated.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: downloads.appendingPathComponent("TAUdo__7__1__big.pdf.crdownload").path))
        XCTAssertFalse(fm.fileExists(atPath: downloads.appendingPathComponent("TAUdo__7__2__Problem sets.zip").path))
    }
}

final class DownloadSafetyTests: XCTestCase {
    func testRedownloadNeverOverwritesYourFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads"), course = root.appendingPathComponent("Course")
        let section = course.appendingPathComponent("Moodle/01 Intro/Starter")
        try fm.createDirectory(at: section, withIntermediateDirectories: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data("my edited work".utf8).write(to: section.appendingPathComponent("main.tex"))
        try Data("same".utf8).write(to: section.appendingPathComponent("same.txt"))
        try Data("v1".utf8).write(to: section.appendingPathComponent("hw.txt"))
        // The lecturer's zip again: original main.tex (different content) and an unchanged file.
        let stage = root.appendingPathComponent("stage")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try Data("template".utf8).write(to: stage.appendingPathComponent("main.tex"))
        try Data("same".utf8).write(to: stage.appendingPathComponent("same.txt"))
        try Data("v2".utf8).write(to: stage.appendingPathComponent("hw.txt"))
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", stage.path, downloads.appendingPathComponent("TAUdo__7__1__Starter.zip").path]
        try zip.run(); zip.waitUntilExit()
        // Firefox: an empty placeholder next to the .part being written.
        try Data().write(to: downloads.appendingPathComponent("TAUdo__7__1__slides.pdf"))
        try Data("partial".utf8).write(to: downloads.appendingPathComponent("TAUdo__7__1__slides.pdf.part"))

        let m = DownloadManifest(courseID: 7, name: "Course", sections: ["1": "Intro"], count: 2)
        let moved = DownloadMover.run([(m, course)], downloads: downloads, now: Date().addingTimeInterval(10))
        XCTAssertEqual(moved[7], 1)
        XCTAssertEqual(try String(contentsOf: section.appendingPathComponent("main.tex"), encoding: .utf8), "my edited work")
        XCTAssertEqual(try String(contentsOf: section.appendingPathComponent("main 2.tex"), encoding: .utf8), "template")
        XCTAssertFalse(fm.fileExists(atPath: section.appendingPathComponent("same 2.txt").path), "identical re-download isn't duplicated")
        XCTAssertEqual(try String(contentsOf: section.appendingPathComponent("hw 2.txt"), encoding: .utf8), "v2", "same size, new content is kept")
        XCTAssertTrue(fm.fileExists(atPath: downloads.appendingPathComponent("TAUdo__7__1__slides.pdf").path), "in-progress download left alone")
    }

    func testCourseMatchingKeepsNumbers() {
        var d = AppData(courses: [.standard("פיזיקה 1"), .standard("פיזיקה 2")])
        XCTAssertEqual(d.course(matching: "0321111101 - פיזיקה 2"), 1)
        XCTAssertEqual(d.course(matching: "0321111001 - פיזיקה 1"), 0)
        XCTAssertNil(d.course(matching: "פיזיקה"), "ambiguous")
        d.courses[0].moodleKey = "0321111001 - פיזיקה 1"
        XCTAssertEqual(d.course(matching: "פיזיקה 1"), 0, "exact link wins")
    }

    func testDueGroups() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 22))!
        func group(_ hours: Double) -> DueGroup { DueGroup.of(now.addingTimeInterval(hours * 3600), now: now, calendar: cal) }
        XCTAssertEqual(group(-1), .overdue)
        XCTAssertEqual(group(1), .today)
        // Three hours from 22:00 is already tomorrow's date, even though it's under a day away.
        XCTAssertEqual(group(3), .tomorrow)
        XCTAssertEqual(group(25), .tomorrow)
        XCTAssertEqual(group(27), .thisWeek)
        XCTAssertEqual(group(6 * 24), .thisWeek)
        XCTAssertEqual(group(7 * 24), .later)
        XCTAssertEqual(group(2), .today, "due at midnight: the end of today, as in the calendar")
    }

    func testAutoLinkSkipsIgnoredCourses() {
        var d = AppData(courses: [Course.standard("Linear Algebra")])
        d.events = [MoodleEvent(uid: "1", summary: "HW 1", categories: ["0366111101 - Linear Algebra 1a"], start: .now, end: .now)]
        d.ignoredCourseKeys = ["0366111101 - Linear Algebra 1a"]
        d.autoLinkCourses(files: [:])
        XCTAssertNil(d.courses[0].moodleKey)
        d.ignoredCourseKeys = []
        d.autoLinkCourses(files: [:])
        XCTAssertEqual(d.courses[0].moodleKey, "0366111101 - Linear Algebra 1a")
    }

    /// A deadline at midnight is in the digest of the day it ends, not the day after.
    func testDigestMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8))!
        let midnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let d = Deadline(event: MoodleEvent(uid: "m", summary: "HW 1", start: midnight, end: midnight), courseIndex: nil, cell: nil, isDone: false)
        XCTAssertEqual(Digest.text([d], morning: morning, courseName: { _ in "" }, calendar: cal)?.body.hasPrefix(String(localized: "Today:")), true)
        XCTAssertNil(Digest.text([d], morning: midnight + 8 * 3600, courseName: { _ in "" }, calendar: cal), "already past")
    }

    func testArazimExams() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ICS.defaultTimeZone
        let oct = cal.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let mar = cal.date(from: DateComponents(year: 2027, month: 3, day: 14))!
        XCTAssertEqual(Arazim.catalogURL(semesterStart: oct).lastPathComponent, "courses-2027a.json")
        XCTAssertEqual(Arazim.catalogURL(semesterStart: mar).lastPathComponent, "courses-2027b.json")
        XCTAssertEqual(Arazim.courseNumber(moodleKey: "0366110001 - חשבון"), "03661100")
        XCTAssertNil(Arazim.courseNumber(moodleKey: "General"))

        // A midterm and a final in the same moed, and an exam with no time.
        let json = #"{"03661100": {"name": "x", "exams": [{"moed": "א", "date": "08/03/2027", "hour": "09:00", "type": "בחינה סופית"},"#
            + #"{"moed": "א", "date": "23/11/2026", "hour": "08:00", "type": "בחינת ביניים"},"#
            + #"{"moed": "ב", "date": "02/04/2027", "hour": "", "type": ""}]}, "03211100": {"name": "y"}}"#
        // Two Moodle groups of the same course list its exams once.
        let ex = try Arazim.exams(catalog: Data(json.utf8), moodleKeys: ["0366110001 - חשבון", "0366110002 - חשבון", "0321110001 - אלגברה"])
        XCTAssertEqual(ex.map(\.uid), ["arazim-03661100-א-2027-03-08", "arazim-03661100-א-2026-11-23", "arazim-03661100-ב-2027-04-02"])
        XCTAssertEqual(ex[0].due, cal.date(from: DateComponents(year: 2027, month: 3, day: 8, hour: 9)))
        XCTAssertEqual(ex[0].courseKey, "0366110001 - חשבון")
        XCTAssertTrue(ex.allSatisfy { Classifier.isExam($0.summary) })
        // No time: all day, and not overdue until the day is over.
        XCTAssertTrue(ex[2].isAllDay)
        XCTAssertEqual(ex[2].start, cal.date(from: DateComponents(year: 2027, month: 4, day: 2)))
        XCTAssertEqual(ex[2].due, cal.date(from: DateComponents(year: 2027, month: 4, day: 2, hour: 23, minute: 59, second: 59)))

        var d = AppData(courses: [])
        d.exams = ex
        d.ignoredCourseKeys = ["0366110001 - חשבון"]
        XCTAssertTrue(d.deadlines().isEmpty)
        // Turning Arazim off hides its exams without forgetting them.
        d.ignoredCourseKeys = []
        XCTAssertEqual(d.deadlines().count, 3)
        d.settings.fetchExams = false
        XCTAssertTrue(d.deadlines().isEmpty)
    }

    func testAllDayEvents() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        func at(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d, hour: h, minute: m))! }
        // An evening deadline sits on its own day; a midnight one ends the day before.
        XCTAssertEqual(AllDay.day(of: at(3, 23, 29), isDeadline: true, calendar: cal), at(3, 0, 0))
        XCTAssertEqual(AllDay.day(of: at(4, 0, 0), isDeadline: true, calendar: cal), at(3, 0, 0))
        XCTAssertEqual(AllDay.day(of: at(4, 0, 0), isDeadline: false, calendar: cal), at(4, 0, 0))
        XCTAssertEqual(AllDay.time(at(3, 23, 29), day: at(3, 0, 0), calendar: cal), "23:29")
        XCTAssertEqual(AllDay.time(at(4, 0, 0), day: at(3, 0, 0), calendar: cal), "24:00")
        // Alerts still fire 1 day and 3 hours before 23:29.
        let due = at(3, 23, 29), day = at(3, 0, 0)
        let fire = AllDay.alarms(leadMinutes: [1440, 180], due: due, day: day).map { day.addingTimeInterval(-$0) }
        XCTAssertEqual(fire, [at(2, 23, 29), at(3, 20, 29)])
    }
}

final class RecordingTests: XCTestCase {
    private func rec(_ name: String, _ host: String = "tau.cloud.panopto.eu") -> Recording {
        Recording(name: name, url: URL(string: "https://\(host)/Panopto/Pages/Viewer.aspx?id=\(UUID().uuidString)")!)
    }

    func testNumbersAndKinds() {
        XCTAssertEqual(Recordings.number("07 - מכניקה אנליטית - תרגול 07"), 7)
        XCTAssertEqual(Recordings.number("שיטות בפיזיקה עיונית 1 - הרצאה 12"), 12, "the keyword beats the course's number")
        XCTAssertEqual(Recordings.number("Lecture #3 (2026-11-03)"), 3)
        XCTAssertEqual(Recordings.number("שיעור 04"), 4)
        XCTAssertNil(Recordings.number("שיטות בפיזיקה עיונית 1 - 03/11/2026"), "a date isn't a session number")
        XCTAssertNil(Recordings.number("0366110001 - חשבון דיפרנציאלי"))
        XCTAssertEqual(Recordings.kind("07 - מכניקה אנליטית - תרגול 07"), .recitation)
        XCTAssertEqual(Recordings.kind("Tutorial 2"), .recitation)
        XCTAssertEqual(Recordings.kind("הרצאה 5"), .lecture)
    }

    func testByCubeAndOrder() {
        let list = [rec("תרגול 2"), rec("הרצאה 10"), rec("הרצאה 2"), rec("סיכום הקורס"), rec("הרצאה 2 - חלק ב")]
        let m = Recordings.byCube(list)
        XCTAssertEqual(m[.lecture]?[2]?.map(\.name), ["הרצאה 2", "הרצאה 2 - חלק ב"])
        XCTAssertEqual(m[.recitation]?[2]?.count, 1)
        XCTAssertEqual(Recordings.sorted(list).map(\.name), ["הרצאה 2", "הרצאה 2 - חלק ב", "הרצאה 10", "תרגול 2", "סיכום הקורס"])
    }

    /// The bookmark's list keeps only https Panopto viewer links, per course.
    func testPayloadRecordings() throws {
        let json = #"{"base": "https://moodle.tau.ac.il", "submitted": [], "v": 4, "recordings": {"0321 - X": ["#
            + #"["הרצאה 1", "https://tau.cloud.panopto.eu/Panopto/Pages/Viewer.aspx?id=abc"], ["evil", "https://evil.example/x"],"#
            + #"["plain", "http://tau.cloud.panopto.eu/x"], ["short"]]}}"#
        var c = URLComponents(string: "taudo://sync")!
        c.queryItems = [URLQueryItem(name: "d", value: json)]
        let p = try XCTUnwrap(MoodleConnect.payload(from: c.url!))
        XCTAssertEqual(p.v, 4)
        XCTAssertEqual(p.validRecordings["0321 - X"]?.map(\.name), ["הרצאה 1"])
        XCTAssertFalse(Recordings.valid(rec("x", "panopto.eu.evil.com")))
    }
}
