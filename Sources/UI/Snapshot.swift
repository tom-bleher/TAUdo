import AppKit
import SwiftUI

/// `TAUdo --demo --snapshot <dir>`: renders the panel and settings offscreen to PNGs (for checks and README screenshots).
/// Language and appearance come from the usual flags, e.g. `-language en -AppleLanguages '(en)'`, `--dark`.
@MainActor
enum Snapshot {
    static func run(into dir: URL, model: AppModel) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await model.scanFiles()
        let dark = CommandLine.arguments.contains("--dark")
        let suffix = "-\(Lang.code)" + (dark ? "-dark" : "")
        let savedTab = UserDefaults.standard.string(forKey: "panelTab")
        defer { UserDefaults.standard.set(savedTab, forKey: "panelTab") }
        for tab in [PanelView.Tab.due, .courses] {
            UserDefaults.standard.set(tab.rawValue, forKey: "panelTab")
            render(PanelView(), model: model, width: PanelView.width, to: dir.appendingPathComponent("panel-\(tab.rawValue)\(suffix).png"), dark: dark)
        }
        let w = SettingsView.width
        render(GeneralSettings(), model: model, width: w, to: dir.appendingPathComponent("settings-general\(suffix).png"), dark: dark)
        render(MoodleSettings(), model: model, width: w, to: dir.appendingPathComponent("settings-moodle\(suffix).png"), dark: dark)
        render(NotificationSettings(), model: model, width: w, to: dir.appendingPathComponent("settings-notifications\(suffix).png"), dark: dark)
        render(CoursesSettings(), model: model, width: w, to: dir.appendingPathComponent("settings-courses\(suffix).png"), dark: dark)
        render(ExamsSettings(), model: model, width: w, to: dir.appendingPathComponent("settings-exams\(suffix).png"), dark: dark)
        render(WelcomeView(onDone: {}), model: model, width: 520, to: dir.appendingPathComponent("welcome\(suffix).png"), dark: dark)
        UserDefaults.standard.set(savedTab, forKey: "panelTab")
        NSApp.terminate(nil)
    }

    private static func render<V: View>(_ view: V, model: AppModel, width: CGFloat, height: CGFloat? = nil, to url: URL, dark: Bool) {
        let root = view
            .environment(model)
            .environment(\.locale, Lang.locale)
            .environment(\.layoutDirection, Lang.direction)
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (geometry callbacks, async state) before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
