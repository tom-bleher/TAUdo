import Foundation
import UserNotifications

/// Local notifications: reminders before open deadlines, a morning summary, and one-off alerts.
/// Scheduled reminders are rebuilt from scratch on every change.
@MainActor
enum Notifier {
    nonisolated private static let prefix = "due."
    nonisolated private static let digestPrefix = "digest."
    nonisolated static let category = "deadline", doneAction = "done"
    private static var center: UNUserNotificationCenter { .current() }
    /// Whether notifications play a sound (Settings › Notifications).
    static var sound = true

    /// Registers the "Mark done" button shown on deadline reminders.
    static func registerActions() {
        let done = UNNotificationAction(identifier: doneAction, title: String(localized: "Mark done"))
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

    /// Whether macOS lets TAUdo show notifications (nil: not asked yet).
    static func isAllowed() async -> Bool? {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: nil
        case .denied: false
        default: true
        }
    }

    struct Plan {
        var deadlines: [Deadline]
        var courseName: (Deadline) -> String
        var leadMinutes: [Int]
        /// Reminders before each deadline (off when calendar alerts do this job).
        var reminders: Bool
        var digestHour: Int?
    }

    static func reschedule(_ plan: Plan, now: Date = .now) async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) || $0.hasPrefix(digestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        // macOS caps pending notifications per app (~64), so only the next two weeks.
        let horizon = now.addingTimeInterval(14 * 86400)
        let relative = RelativeDateTimeFormatter()
        relative.locale = Lang.locale
        if plan.reminders {
            for d in plan.deadlines where !d.isDone && d.due > now && d.due < horizon {
                if Task.isCancelled { return }  // superseded by a newer reschedule
                for lead in plan.leadMinutes {
                    let fire = d.due.addingTimeInterval(-Double(lead) * 60)
                    guard fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = d.title
                    content.subtitle = plan.courseName(d)
                    // "in 1 day" as seen when the reminder fires, not when it was scheduled.
                    content.body = String(localized: "Due \(d.due.medium(time: !d.event.isAllDay)) (\(relative.localizedString(for: d.due, relativeTo: fire)))")
                    content.sound = sound ? .default : nil
                    content.categoryIdentifier = category
                    await add("\(prefix)\(d.id).\(lead)", content, at: fire, now: now)
                }
            }
        }
        if let hour = plan.digestHour {
            let cal = Calendar.current
            for k in 0..<7 {
                if Task.isCancelled { return }
                guard let day = cal.date(byAdding: .day, value: k, to: cal.startOfDay(for: now)),
                      let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now,
                      let text = Digest.text(plan.deadlines, morning: fire, courseName: plan.courseName) else { continue }
                let content = UNMutableNotificationContent()
                content.title = text.title
                content.body = text.body
                content.sound = sound ? .default : nil
                await add("\(digestPrefix)\(Int(day.timeIntervalSince1970))", content, at: fire, now: now)
            }
        }
    }

    /// Shows a notification right away (new or moved deadlines, finished downloads).
    static func post(_ title: String, _ body: String, id: String = UUID().uuidString, open url: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo["open"] = url.path }
        content.sound = sound ? .default : nil
        center.add(UNNotificationRequest(identifier: "alert.\(id)", content: content, trigger: nil))
    }

    private static func add(_ id: String, _ content: UNNotificationContent, at fire: Date, now: Date) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSince(now)), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
