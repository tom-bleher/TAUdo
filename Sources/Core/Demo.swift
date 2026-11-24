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
        let keys = ["0321213001 - שיטות בפיזיקה עיונית 1", "0321210501 - מכניקה אנליטית",
                    "0366110001 - חשבון דיפרנציאלי ואינטגרלי 1א לפיזיקה", "0321110001 - אלגברה לינארית לפיזיקה"]
        for i in d.courses.indices { d.courses[i].moodleKey = keys[i] }
        func ev(_ n: Int, _ key: String, _ title: String, days: Double) -> MoodleEvent {
            let t = now.addingTimeInterval(days * 86400)
            return MoodleEvent(uid: "\(9000 + n)@moodle.tau.ac.il", summary: title, categories: [key], start: t, end: t)
        }
        d.events = [
            ev(1, keys[0], "יש להגיש את 'תרגיל בית 7'", days: -2),
            ev(2, keys[0], "יש להגיש את 'תרגיל בית 8'", days: 2.3),
            ev(3, keys[1], "יש להגיש את 'תרגיל בית 8 - קבוצה 4'", days: 0.2),
            ev(4, keys[2], "יש להגיש את 'תרגיל בית 3'", days: 4),
            ev(5, keys[3], "יש להגיש את 'הגשת שיעורי בית 4'", days: 6.5),
            ev(6, keys[2], "תאריך הגשה בוחן אמצע", days: 9),
            ev(7, keys[1], "יש להגיש את 'תרגיל בית 7 - קבוצה 4'", days: -5),
            ev(8, keys[0], "הרצאה 15 - טורי פורייה", days: 1),
            ev(9, "0321180101 - מעבדה בפיזיקה 1", "יש להגיש את 'דו\"ח מעבדה 3'", days: 3.5),
        ]
        d.manual = [ManualDeadline(title: "מבחן אמצע", due: now.addingTimeInterval(12 * 86400), courseID: d.courses[3].id)]
        d.lastSync = now
        d.settings.exportURL = "https://moodle.tau.ac.il/calendar/export_execute.php?userid=12345&authtoken=demo"
        return d
    }
}
