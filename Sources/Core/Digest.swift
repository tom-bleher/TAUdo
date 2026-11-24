import Foundation

/// The morning summary: what's due today and tomorrow.
enum Digest {
    /// nil when nothing is due today or tomorrow (no notification that morning).
    static func text(_ deadlines: [Deadline], morning: Date, courseName: (Deadline) -> String,
                     calendar cal: Calendar = .current) -> (title: String, body: String)? {
        let today = cal.startOfDay(for: morning)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              let after = cal.date(byAdding: .day, value: 2, to: today) else { return nil }
        let open = deadlines.filter { !$0.isDone }
        let dueToday = open.filter { $0.due >= morning && $0.due < tomorrow }
        let dueTomorrow = open.filter { $0.due >= tomorrow && $0.due < after }
        guard !dueToday.isEmpty || !dueTomorrow.isEmpty else { return nil }
        let line = { (d: Deadline) in "• \(d.title) · \(courseName(d))" }
        var parts: [String] = []
        if !dueToday.isEmpty { parts.append(String(localized: "Today:") + "\n" + dueToday.map(line).joined(separator: "\n")) }
        if !dueTomorrow.isEmpty { parts.append(String(localized: "Tomorrow:") + "\n" + dueTomorrow.map(line).joined(separator: "\n")) }
        let title = dueToday.isEmpty ? String(localized: "\(dueTomorrow.count) due tomorrow")
                                     : String(localized: "\(dueToday.count) due today")
        return (title, parts.joined(separator: "\n"))
    }
}
