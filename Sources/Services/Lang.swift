import AppKit
import Foundation
import SwiftUI

/// App language. Hebrew by default; English can be chosen in Settings (the app relaunches to apply it).
enum Lang {
    private static let key = "language"
    static let supported = ["he", "en"]

    static var code: String { UserDefaults.standard.string(forKey: key).flatMap { supported.contains($0) ? $0 : nil } ?? "he" }
    static var isHebrew: Bool { code == "he" }
    static var locale: Locale { Locale(identifier: isHebrew ? "he_IL" : "en_IL") }
    static var direction: LayoutDirection { isHebrew ? .rightToLeft : .leftToRight }

    /// Must run before any localized string is looked up: pins the bundle's localization to the chosen language.
    static func apply() {
        // Snapshot runs pass -AppleLanguages on the command line; don't persist that into your preferences.
        guard !CommandLine.arguments.contains("--snapshot") else { return }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        // Window chrome (toolbar tab order, window buttons) follows the system's direction, not the app's language: pin it too.
        for key in ["AppleTextDirection", "NSForceRightToLeftWritingDirection"] { UserDefaults.standard.set(isHebrew, forKey: key) }
    }

    static func set(_ new: String) {
        guard new != code else { return }
        UserDefaults.standard.set(new, forKey: key)
        apply()
        relaunch()
    }

    /// Joins short pieces of text with " · ", keeping each piece intact and the pieces in the UI's reading order
    /// when Hebrew and Latin text are mixed (a Hebrew course name next to an English date, say).
    static func joined(_ parts: String...) -> String {
        (isHebrew ? "\u{200F}" : "\u{200E}") + parts.map { "\u{2068}\($0)\u{2069}" }.joined(separator: " · ")
    }

    /// Keeps text that reads left to right (a signed number like "+3") in its order inside Hebrew text, where it
    /// would otherwise show as "3+".
    static func ltr(_ s: String) -> String { "\u{2066}\(s)\u{2069}" }

    private static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

extension Date {
    /// "בעוד יומיים" / "in 2 days", in the app's language.
    func relative(to now: Date = .now) -> String {
        formatted(.relative(presentation: .named).locale(Lang.locale))
    }

    func long(time: Bool = true) -> String {
        formatted(Date.FormatStyle(date: .complete, time: time ? .shortened : .omitted, locale: Lang.locale))
    }

    func medium(time: Bool = true) -> String {
        formatted(Date.FormatStyle(date: .abbreviated, time: time ? .shortened : .omitted, locale: Lang.locale))
    }

    /// When a deadline falls, as short as its section allows: the time alone today and tomorrow,
    /// the weekday within a week, otherwise the date. All-day items (`time: false`) show the day only.
    func dueLabel(_ group: DueGroup, time: Bool = true) -> String {
        let f = Date.FormatStyle(locale: Lang.locale)
        // A deadline at midnight ends the day before: shown on that day at 24:00, as in the calendar.
        let midnight = time && AllDay.day(of: self, isDeadline: true) < Calendar.current.startOfDay(for: self)
        switch group {
        case .today, .tomorrow:
            guard time else { return formatted(f.weekday(.wide)) }
            return midnight ? "24:00" : formatted(f.hour().minute())
        case .thisWeek:
            if midnight { return addingTimeInterval(-1).formatted(f.weekday(.wide)) + " 24:00" }
            return formatted(time ? f.weekday(.wide).hour().minute() : f.weekday(.wide))
        case .overdue, .later: return formatted(time ? f.day().month(.abbreviated).hour().minute() : f.day().month(.abbreviated))
        }
    }
}
