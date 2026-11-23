import EventKit
import Foundation

/// Mirrors Moodle events into one dedicated Apple Calendar calendar. Only touches that calendar.
@MainActor
final class CalendarSync {
    struct Planned {
        var uid: String
        var title: String
        var start: Date
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

    /// Finds the calendar by id, else by name, else creates it (iCloud if available, otherwise On My Mac).
    func calendar(id: String?, name: String) throws -> EKCalendar {
        if let id, let c = store.calendar(withIdentifier: id) {
            if c.title != name { c.title = name; try store.saveCalendar(c, commit: true) }
            return c
        }
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

    /// Creates/updates events by Moodle UID; deletes future events that left the feed. Past events are kept.
    func sync(_ planned: [Planned], into cal: EKCalendar, now: Date = .now) throws -> (created: Int, updated: Int, deleted: Int) {
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
            // Calendar servers may reorder alarms and store all-day ends differently: compare loosely.
            let alarmOffsets = (e.alarms ?? []).map { -$0.relativeOffset }.sorted()
            if !isNew, e.title == p.title, e.startDate == p.start, p.isAllDay || e.endDate == p.end, e.isAllDay == p.isAllDay,
               e.notes == notes, e.url == p.url, alarmOffsets == p.alarms.sorted() { continue }
            if isNew { e.calendar = cal }
            e.title = p.title; e.startDate = p.start; e.endDate = p.end; e.isAllDay = p.isAllDay
            e.notes = notes; e.url = p.url
            e.alarms = p.alarms.map { EKAlarm(relativeOffset: -$0) }
            try store.save(e, span: .thisEvent, commit: false)
            if isNew { created += 1 } else { updated += 1 }
        }
        for e in existing.values where e.startDate >= now {
            try store.remove(e, span: .thisEvent, commit: false); deleted += 1
        }
        try store.commit()
        return (created, updated, deleted)
    }

    static func uid(_ notes: String?) -> String? {
        guard let notes, let r = notes.range(of: marker, options: .backwards) else { return nil }
        return notes[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
