import Foundation

/// Sections of the Deadlines tab, by calendar day.
enum DueGroup: Int, CaseIterable, Sendable {
    case overdue, today, tomorrow, thisWeek, later

    static func of(_ due: Date, now: Date, calendar: Calendar = .current) -> DueGroup {
        if due < now { return .overdue }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .tomorrow
        case 2..<7: return .thisWeek
        default: return .later
        }
    }

    var label: String {
        switch self {
        case .overdue: String(localized: "Overdue")
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .thisWeek: String(localized: "Next 7 days")
        case .later: String(localized: "Later")
        }
    }
}
