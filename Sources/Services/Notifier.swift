import Foundation
import UserNotifications

/// Local reminders for open deadlines. Rebuilt from scratch on every change.
@MainActor
enum Notifier {
    nonisolated private static let prefix = "due."
    private static var center: UNUserNotificationCenter { .current() }

    nonisolated static let category = "deadline", doneAction = "done"

    /// Registers the "Mark done" button shown on deadline reminders.
    static func registerActions() {
        let done = UNNotificationAction(identifier: doneAction, title: "Mark done")
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [done], intentIdentifiers: [])])
    }

    /// The deadline UID a reminder belongs to ("due.<uid>.<lead>").
    nonisolated static func uid(fromRequest id: String) -> String? {
        guard id.hasPrefix(prefix), let dot = id.lastIndex(of: ".") else { return nil }
        return String(id[id.index(id.startIndex, offsetBy: prefix.count)..<dot])
    }

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(_ deadlines: [Deadline], courseNames: [Int: String], leadMinutes: [Int], enabled: Bool, now: Date = .now) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        // macOS caps pending notifications per app (~64), so only the next two weeks.
        let horizon = now.addingTimeInterval(14 * 86400)
        let relative = RelativeDateTimeFormatter()
        for d in deadlines where !d.isDone && d.due > now && d.due < horizon {
            if Task.isCancelled { return }  // superseded by a newer reschedule
            for lead in leadMinutes {
                let fire = d.due.addingTimeInterval(-Double(lead) * 60)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = d.title
                content.subtitle = d.courseIndex.flatMap { courseNames[$0] } ?? d.event.courseKey ?? ""
                // "in 1 day" as seen when the reminder fires, not when it was scheduled.
                content.body = "Due " + d.due.formatted(date: .abbreviated, time: .shortened) + " (" + relative.localizedString(for: d.due, relativeTo: fire) + ")"
                content.sound = .default
                content.categoryIdentifier = category
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(d.id).\(lead)", content: content, trigger: trigger))
            }
        }
    }
}
