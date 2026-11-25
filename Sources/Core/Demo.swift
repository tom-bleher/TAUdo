import Foundation

/// Sample data for `--demo`, snapshots and tests: four courses and Moodle deadlines (in TAU's Hebrew format) around `now`.
enum Demo {
    static func data(now: Date) -> AppData {
        var d = AppData(courses: [
            .standard("שיטות בפיזיקה עיונית 1", lectures: String(repeating: "d", count: 13) + "s", recitations: "dddddt", homework: "ddddddt"),
            .standard("מכניקה אנליטית", pace: .selfStudy, lectures: String(repeating: "d", count: 26), recitations: "ddddddddrdddd", homework: "dddddd.d.dddd"),
            .standard("חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה", lectures: "ddddddddd", recitations: "dddd", homework: "dd"),
            .standard("אלגברה לינארית לפיזיקה", lectures: "dddddddddd", recitations: "ddd", homework: "ddd"),
        ])
        d.onboarded = true
        d.settings.selfStudy = true
        let keys = ["0321213001 - שיטות בפיזיקה עיונית 1", "0321210501 - מכניקה אנליטית",
                    "0366110001 - חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה", "0321110001 - אלגברה לינארית לפיזיקה"]
        for i in d.courses.indices { d.courses[i].moodleKey = keys[i] }
        // Deadlines at the times Moodle uses (23:59, noon), `days` after `now`'s day.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ICS.defaultTimeZone
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: days, to: now)!)!
        }
        func ev(_ n: Int, _ key: String, _ title: String, _ t: Date) -> MoodleEvent {
            MoodleEvent(uid: "\(9000 + n)@moodle.tau.ac.il", summary: title, categories: [key], start: t, end: t)
        }
        // One due within hours: tonight, or tomorrow noon when it's already late.
        let soon = at(0, 23, 59) > now.addingTimeInterval(2 * 3600) ? at(0, 23, 59) : at(1, 12)
        d.events = [
            ev(1, keys[0], "יש להגיש את 'תרגיל בית 7'", at(-2, 23, 59)),
            ev(2, keys[0], "יש להגיש את 'תרגיל בית 8'", at(2, 23, 59)),
            ev(3, keys[1], "יש להגיש את 'תרגיל בית 8 - קבוצה 4'", soon),
            ev(4, keys[2], "יש להגיש את 'תרגיל בית 3'", at(4, 23, 59)),
            ev(5, keys[3], "יש להגיש את 'הגשת שיעורי בית 4'", at(6, 23, 59)),
            ev(6, keys[2], "תאריך הגשה בוחן אמצע", at(9, 12)),
            ev(7, keys[1], "יש להגיש את 'תרגיל בית 7 - קבוצה 4'", at(-5, 12)),
            ev(8, keys[0], "הרצאה 15 - טורי פורייה", at(1, 12)),
        ]
        d.exams = [MoodleEvent(uid: "arazim-03212130-א-demo", summary: "בחינה סופית מועד א", categories: [keys[0]],
                               start: at(20, 9), end: at(20, 9))]
        d.manual = [ManualDeadline(title: "מבחן אמצע", due: at(12, 9), courseID: d.courses[3].id)]
        d.lastSync = now
        d.settings.exportURL = "https://moodle.tau.ac.il/calendar/export_execute.php?userid=12345&authtoken=demo"
        d.settings.calendarSync = true
        return d
    }
}
