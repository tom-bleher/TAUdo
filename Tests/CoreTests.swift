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
        XCTAssertTrue(dl.contains { $0.isManual && $0.title == "Midterm" })
        XCTAssertEqual(dl.map(\.due), dl.map(\.due).sorted())
    }

    func testSubmissionsApplyOnce() {
        var d = Demo.data(now: now)
        d.applySubmissions([9002])   // Methods HW 8
        XCTAssertEqual(d.courses[0].tracks[2].cells[7], .done)
        // Untick by hand; the same report must not re-tick it.
        d.setDone(d.deadlines().first { $0.event.moodleEventID == 9002 }!, false)
        d.applySubmissions([9002])
        XCTAssertEqual(d.courses[0].tracks[2].cells[7], .empty)
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
        XCTAssertEqual(Pacing.behind(t, planned: 6), 2)
        var c = Course(name: "c", pace: .selfStudy, tracks: [t])
        var s = Settings()
        s.semesterStart = Settings.day(2026, 10, 1)
        c.targetDate = Settings.day(2026, 10, 11)
        XCTAssertEqual(Pacing.plannedPosition(t, course: c, classPos: 3, settings: s, now: Settings.day(2026, 10, 6)), 5)
        c.pace = .withClass
        XCTAssertEqual(Pacing.plannedPosition(t, course: c, classPos: 3, settings: s, now: Settings.day(2026, 10, 6)), 3)
    }
}

final class PersistenceTests: XCTestCase {
    func testImportTrackHTML() throws {
        let json = #"[{"name":"Methods","rows":[["done","done","skipped"],["todo"],["","done"]]},{"name":"Old","weeks":[["done","revisit","todo"]]}]"#
        let c = try AppData.importTrackHTML(json)
        XCTAssertEqual(c.map(\.name), ["Methods", "Old"])
        XCTAssertEqual(c[0].tracks.map(\.count), [25, 13, 13])
        XCTAssertEqual(c[0].tracks[0].cells.prefix(3), [.done, .done, .skipped])
        XCTAssertEqual(c[1].tracks[1].cells.first, .revisit)
        XCTAssertEqual(c[1].tracks[2].cells.first, .todo)
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
        let json = #"{"key":"k","base":"https://moodle.tau.ac.il","exportURL":null,"assignIDs":[1,2,3],"pendingIDs":[2],"courses":{"0321-1":"Physics"}}"#
        var c = URLComponents(string: "taudo://sync")!
        c.queryItems = [URLQueryItem(name: "d", value: json)]
        let p = try XCTUnwrap(MoodleConnect.payload(from: c.url!))
        XCTAssertEqual(p.submittedIDs, [1, 3])
        XCTAssertEqual(p.key, "k")
        XCTAssertEqual(p.courses?["0321-1"], "Physics")
        XCTAssertNil(MoodleConnect.payload(from: URL(string: "taudo://other?d=x")!))
    }

    func testBookmarkletIsValidJavaScript() throws {
        // Decodes the javascript: URL and syntax-checks it with JavaScriptCore.
        let code = try XCTUnwrap(MoodleConnect.bookmarkletURL(key: "k").dropFirst("javascript:".count).removingPercentEncoding)
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
        XCTAssertEqual(f.urls(.lecture, 3).map(\.pathExtension), ["mkv"], "notes PDFs aren't lectures")
        XCTAssertEqual(f.urls(.lecture, 4).count, 1)
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
