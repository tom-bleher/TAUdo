import EventKit
import Foundation

/// Mirrors Moodle events into one dedicated Apple Calendar calendar. Only touches that calendar.
@MainActor
final class CalendarSync {
    struct Planned {
        var uid: String
        var title: String
        var start: Date
        /// For all-day events, the last day (inclusive): a one-day event has `end == start`.
        var end: Date
        var isAllDay: Bool
        var notes: String
        var url: URL?
        /// Seconds before start; empty = no alerts.
        var alarms: [TimeInterval]
    }

    private let store = EKEventStore()
    private static let marker = "moodle-uid:"

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// A calendar TAUdo can write to, for the picker in Settings.
    struct Choice: Hashable {
        var id: String
        var title: String
        /// The account it belongs to: "iCloud", a Google address, "On My Mac", …
        var account: String
    }

    /// Calendars you can add events to, grouped by account. A Google account added in
    /// System Settings › Internet Accounts shows up here, so TAUdo can write straight into Google Calendar.
    func writableCalendars() -> [Choice] {
        store.calendars(for: .event).filter(\.allowsContentModifications)
            .map { Choice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "") }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    /// Finds the calendar by id, else by name, else creates it (iCloud if available, otherwise On My Mac).
    /// Never renames: the calendar may be one of yours that you picked in Settings.
    func calendar(id: String?, name: String) throws -> EKCalendar {
        if let id, let c = store.calendar(withIdentifier: id) { return c }
        if let c = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) { return c }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = name
        c.cgColor = CGColor(red: 0.18, green: 0.62, blue: 0.36, alpha: 1)
        c.source = store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.defaultCalendarForNewEvents?.source
        try store.saveCalendar(c, commit: true)
        return c
    }

    /// Creates/updates events by Moodle UID and deletes ones no longer wanted from `keepBefore` on.
    /// Older events are kept: TAUdo only remembers this semester, so they're last semester's history.
    func sync(_ planned: [Planned], into cal: EKCalendar, keepBefore: Date, now: Date = .now) throws -> (created: Int, updated: Int, deleted: Int) {
        let lo = min(planned.map(\.start).min() ?? now, now).addingTimeInterval(-86400)
        let hi = max(planned.map(\.end).max() ?? now, now).addingTimeInterval(400 * 86400)
        var existing: [String: EKEvent] = [:]
        for e in store.events(matching: store.predicateForEvents(withStart: lo, end: hi, calendars: [cal])) {
            guard let uid = Self.uid(e.notes) else { continue }
            if existing[uid] != nil { try store.remove(e, span: .thisEvent, commit: false) } else { existing[uid] = e }
        }
        var created = 0, updated = 0, deleted = 0
        for p in planned {
            let e = existing.removeValue(forKey: p.uid) ?? EKEvent(eventStore: store)
            let isNew = e.calendar == nil
            let notes = p.notes.isEmpty ? Self.marker + p.uid : p.notes + "\n\n" + Self.marker + p.uid
            // Calendar servers may reorder alarms and store an all-day end as 23:59:59 or the next midnight:
            // compare loosely.
            let alarmOffsets = (e.alarms ?? []).map { -$0.relativeOffset }.sorted()
            if !isNew, e.title == p.title, e.startDate == p.start, e.isAllDay == p.isAllDay,
               p.isAllDay ? Calendar.current.isDate(e.endDate.addingTimeInterval(-1), inSameDayAs: p.end) : e.endDate == p.end,
               e.notes == notes, e.url == p.url, alarmOffsets == p.alarms.sorted() { continue }
            if isNew { e.calendar = cal }
            e.title = p.title; e.startDate = p.start; e.endDate = p.end; e.isAllDay = p.isAllDay
            e.notes = notes; e.url = p.url
            e.alarms = p.alarms.map { EKAlarm(relativeOffset: -$0) }
            try store.save(e, span: .thisEvent, commit: false)
            if isNew { created += 1 } else { updated += 1 }
        }
        for e in existing.values where e.startDate >= min(keepBefore, now) {
            try store.remove(e, span: .thisEvent, commit: false); deleted += 1
        }
        try store.commit()
        return (created, updated, deleted)
    }

    /// Deletes the events TAUdo put in a calendar (and nothing else), e.g. after you pick another calendar.
    func removeOurEvents(fromCalendar id: String, now: Date = .now) throws {
        guard let cal = store.calendar(withIdentifier: id) else { return }
        for e in ourEvents(in: cal, now: now) { try store.remove(e, span: .thisEvent, commit: false) }
        try store.commit()
    }

    /// Drops the alerts from TAUdo's events in a calendar and keeps the events (after calendar sync is turned off).
    /// Never creates the calendar or an event.
    func removeAlarms(fromCalendar id: String, now: Date = .now) throws {
        guard let cal = store.calendar(withIdentifier: id) else { return }
        for e in ourEvents(in: cal, now: now) where !(e.alarms ?? []).isEmpty {
            e.alarms = nil
            try store.save(e, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    private func ourEvents(in cal: EKCalendar, now: Date) -> [EKEvent] {
        let year: TimeInterval = 365 * 86400
        // Event queries span at most four years.
        return store.events(matching: store.predicateForEvents(withStart: now - 2 * year, end: now + 2 * year, calendars: [cal]))
            .filter { Self.uid($0.notes) != nil }
    }

    static func uid(_ notes: String?) -> String? {
        guard let notes, let r = notes.range(of: marker, options: .backwards) else { return nil }
        return notes[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
