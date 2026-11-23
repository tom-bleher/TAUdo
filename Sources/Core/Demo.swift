import Foundation

/// Sample Moodle data for `--demo` and tests: the track.html seed plus deadlines around `now`.
enum Demo {
    static func data(now: Date) -> AppData {
        var d = AppData.initial
        let keys = ["0321-2113-01", "0321-2122-01", "0366-1121-01", "0366-1141-01"]
        for i in d.courses.indices { d.courses[i].moodleKey = keys[i] }
        func ev(_ n: Int, _ key: String, _ title: String, days: Double) -> MoodleEvent {
            let t = now.addingTimeInterval(days * 86400)
            return MoodleEvent(uid: "\(9000 + n)@moodle.tau.ac.il", summary: title, categories: [key], start: t, end: t)
        }
        d.events = [
            ev(1, keys[0], "תרגיל בית 7 is due", days: -2),
            ev(2, keys[0], "תרגיל בית 8 is due", days: 2.3),
            ev(3, keys[1], "Problem Set 8 is due", days: 0.2),
            ev(4, keys[2], "תרגיל בית 6 is due", days: 4),
            ev(5, keys[3], "HW 5 is due", days: 6.5),
            ev(6, keys[2], "בוחן אמצע", days: 9),
            ev(7, keys[1], "Problem Set 7 is due", days: -5),
            ev(8, keys[0], "הרצאה 15 - טורי פורייה", days: 1),
            ev(9, "0321-1801-01", "דו\"ח מעבדה 3 is due", days: 3.5),
        ]
        d.moodleCourseNames = ["0321-1801-01": "מעבדה בפיזיקה 1 - Physics Lab 1"]
        d.manual = [ManualDeadline(title: "Midterm", due: now.addingTimeInterval(12 * 86400), courseID: d.courses[3].id)]
        d.lastSync = now
        d.settings.exportURL = "https://moodle.tau.ac.il/2026/calendar/export_execute.php?userid=1&authtoken=demo"
        return d
    }
}
