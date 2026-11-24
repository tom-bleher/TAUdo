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
    }

    static func set(_ new: String) {
        guard new != code else { return }
        UserDefaults.standard.set(new, forKey: key)
        apply()
        relaunch()
    }

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

    func medium() -> String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Lang.locale))
    }
}
