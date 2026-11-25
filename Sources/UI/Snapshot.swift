import AppKit
import SwiftUI

/// `TAUdo --demo --snapshot <dir>`: renders the panel, the app in the menu bar, and settings offscreen to PNGs
/// (for checks and README screenshots).
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
        for tab in [PanelView.Tab.due, .exams, .courses] {
            UserDefaults.standard.set(tab.rawValue, forKey: "panelTab")
            render(PanelView(), model: model, width: PanelView.width, to: dir.appendingPathComponent("panel-\(tab.rawValue)\(suffix).png"), dark: dark)
        }
        UserDefaults.standard.set(PanelView.Tab.due.rawValue, forKey: "panelTab")
        // The Deadlines tab's other states: adding a deadline, done ones listed, a hidden course in the footer.
        var busy = model.data
        if let d = busy.deadlines().first(where: { $0.due > .now }) { busy.setDone(d, true) }
        let other = "0366111101 - אלגברה לינארית 1א"
        busy.events.append(MoodleEvent(uid: "9100@moodle.tau.ac.il", summary: "יש להגיש את 'תרגיל בית 5'", categories: [other],
                                       start: .now.addingTimeInterval(86400), end: .now.addingTimeInterval(86400)))
        busy.ignoredCourseKeys = [other]
        let savedDone = UserDefaults.standard.object(forKey: "panelShowsDone")
        UserDefaults.standard.set(true, forKey: "panelShowsDone")
        render(PanelView(adding: true), model: AppModel(data: busy, persist: false), width: PanelView.width,
               to: dir.appendingPathComponent("panel-states\(suffix).png"), dark: dark)
        UserDefaults.standard.set(savedDone, forKey: "panelShowsDone")
        render(InMenuBar(dark: dark), model: model, width: InMenuBar.width, to: dir.appendingPathComponent("menubar\(suffix).png"), dark: dark)
        let w = SettingsView.width
        func pane<V: View>(_ name: String, _ view: V) {
            render(view, model: model, width: w, to: dir.appendingPathComponent("settings-\(name)\(suffix).png"), dark: dark)
        }
        pane("general", GeneralSettings())
        pane("menubar", MenuBarSettings())
        pane("moodle", MoodleSettings())
        pane("courses", CoursesSettings())
        pane("exams", ExamsSettings())
        pane("notifications", NotificationSettings())
        pane("calendar", CalendarSettings())
        pane("updates", UpdateSettings())
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

/// The app as you use it: its menu bar item, highlighted, with the panel open below it (centred, as macOS places it).
private struct InMenuBar: View {
    static let margin: CGFloat = 44
    static let width = PanelView.width + 2 * margin
    let dark: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) { MenuBarLabel() }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 9).frame(height: 22)
                .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color(white: dark ? 0.1 : 0.97).opacity(0.92))
            PanelView()
                .frame(width: PanelView.width)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
                .padding(.top, 8).padding(.bottom, Self.margin)
        }
        .frame(width: Self.width)
        .background(LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.13, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.12)]
                                                 : [Color(red: 0.80, green: 0.86, blue: 0.96), Color(red: 0.93, green: 0.90, blue: 0.97)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
