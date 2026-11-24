import Foundation

/// Calendar events are written as all-day events on the day they fall, with the time in the title.
enum AllDay {
    /// The day a moment belongs to. A deadline at exactly midnight ends the previous day ("due 24:00").
    static func day(of date: Date, isDeadline: Bool, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let midnight = c.hour == 0 && c.minute == 0 && c.second == 0
        return calendar.startOfDay(for: isDeadline && midnight ? date.addingTimeInterval(-1) : date)
    }

    /// Reminder lead times (minutes before `due`) as seconds before the start of the all-day event `day`,
    /// so each alert still fires at the same moment before the deadline.
    static func alarms(leadMinutes: [Int], due: Date, day: Date) -> [TimeInterval] {
        leadMinutes.map { Double($0) * 60 - due.timeIntervalSince(day) }
    }

    /// "23:29", or "24:00" for a midnight deadline shown on the day before.
    static func time(_ date: Date, day: Date, calendar: Calendar = .current) -> String {
        if calendar.startOfDay(for: date) > day { return "24:00" }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
