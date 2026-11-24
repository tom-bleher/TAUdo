import Foundation

/// Exam dates from Arazim (arazim-project.com), a student-run mirror of TAU's course catalog.
/// TAU exam dates usually aren't on Moodle.
enum Arazim {
    /// The catalog for a semester, e.g. "courses-2027a" for the semester starting October 2026
    /// (TAU names an academic year after the year it ends; "a" is fall, "b" is spring).
    static func catalogURL(semesterStart: Date) -> URL {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ICS.defaultTimeZone
        let c = cal.dateComponents([.year, .month], from: semesterStart)
        let fall = c.month! >= 8 || c.month! == 1
        let year = c.year! + (c.month! >= 8 ? 1 : 0)
        return URL(string: "https://arazim-project.com/data/courses-\(year)\(fall ? "a" : "b").json")!
    }

    /// "0366110001 - חשבון…" → "03661100": a Moodle shortname starts with the course number and group.
    static func courseNumber(moodleKey: String) -> String? {
        let digits = moodleKey.prefix { $0.isNumber }
        return digits.count >= 8 ? String(digits.prefix(8)) : nil
    }

    private struct Course: Decodable { var exams: [Exam]? }
    private struct Exam: Decodable { var moed: String?; var date: String?; var hour: String?; var type: String? }

    /// One event per exam sitting of each course, filed under its Moodle course. A course number in more than one
    /// Moodle course (two groups) is listed once. An exam without a time is all-day, due at the end of its day.
    static func exams(catalog: Data, moodleKeys: some Sequence<String>) throws -> [MoodleEvent] {
        let courses = try JSONDecoder().decode([String: Course].self, from: catalog)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = ICS.defaultTimeZone
        var seen = Set<String>()
        return moodleKeys.sorted().flatMap { key -> [MoodleEvent] in
            guard let n = courseNumber(moodleKey: key), seen.insert(n).inserted, let exams = courses[n]?.exams else { return [] }
            return exams.compactMap { x in
                guard let day = x.date, let moed = x.moed else { return nil }
                let hour = x.hour.flatMap { $0.isEmpty ? nil : $0 }
                f.dateFormat = hour == nil ? "dd/MM/yyyy" : "dd/MM/yyyy HH:mm"
                guard let at = f.date(from: hour.map { "\(day) \($0)" } ?? day) else { return nil }
                let what = x.type.flatMap { $0.isEmpty ? nil : $0 } ?? "בחינה"
                // A course can have a midterm and a final in the same moed: the date tells them apart.
                let id = day.split(separator: "/").reversed().joined(separator: "-")
                return MoodleEvent(uid: "arazim-\(n)-\(moed)-\(id)", summary: "\(what) מועד \(moed)", categories: [key],
                                   start: at, end: hour == nil ? at.addingTimeInterval(86400 - 1) : at, isAllDay: hour == nil)
            }
        }
    }
}
