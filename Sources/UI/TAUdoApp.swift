import AppKit
import SwiftUI
import UserNotifications

/// Entry point: the language has to be pinned before SwiftUI loads any strings.
@main
enum Entry {
    static func main() {
        Lang.apply()
        TAUdoApp.main()
    }
}

struct TAUdoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { AppDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(model).environment(\.locale, Lang.locale).environment(\.layoutDirection, Lang.direction)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings { SettingsView().environment(model).environment(\.locale, Lang.locale).environment(\.layoutDirection, Lang.direction) }

        Window("Welcome to TAUdo", id: "welcome") { WelcomeWindow().environment(model).environment(\.locale, Lang.locale).environment(\.layoutDirection, Lang.direction) }
            .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// `--demo` uses sample Moodle data in memory and never touches your saved state.
    @MainActor static let model: AppModel = CommandLine.arguments.contains("--demo") ? AppModel(data: Demo.data(now: .now), persist: false) : AppModel()
    private var previewWindow: NSWindow?

    /// "Mark done" on a reminder.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Clicking a "saved files" alert opens the folder.
        if let path = response.notification.request.content.userInfo["open"] as? String {
            await MainActor.run { _ = NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            return
        }
        guard response.actionIdentifier == Notifier.doneAction,
              let uid = Notifier.uid(fromRequest: response.notification.request.identifier) else { return }
        await MainActor.run { Self.model.markDone(uid: uid) }
    }

    /// Show reminders even while the panel is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// taudo://sync links from the bookmarklet.
    @MainActor func application(_ app: NSApplication, open urls: [URL]) {
        urls.forEach(Self.model.handle)
    }

    @MainActor func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerActions()
        Self.model.start()
        _ = Updates.shared
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(i + 1) {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task { await Snapshot.run(into: dir, model: Self.model) }
            return
        }
        // `--preview` shows the menu bar panel in a normal window (for screenshots).
        if CommandLine.arguments.contains("--preview") {
            let w = NSWindow(contentRect: .init(x: 200, y: 200, width: 500, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "TAUdo"
            w.contentView = NSHostingView(rootView: PanelView().environment(Self.model))
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = w
        }
    }
}

/// The welcome window's root: closes itself when done.
struct WelcomeWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View { WelcomeView { dismissWindow(id: "welcome") } }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let label = model.menuLabel
        Image(nsImage: Logo.menuBarImage)
        if let title = label.title {
            Text((label.overdue > 0 ? String(localized: "\(label.overdue) overdue") + " · " : "") + title)
        } else if label.overdue > 0 {
            Text(String(localized: "\(label.overdue) overdue"))
        }
        // First launch: open the welcome window (the label is the one view that exists at launch).
        Color.clear.frame(width: 0, height: 0).onAppear {
            // `--settings` opens the Settings window at launch (for checking its layout).
            if CommandLine.arguments.contains("--settings") { NSApp.activate(ignoringOtherApps: true); openSettings() }
            guard !model.data.onboarded, !CommandLine.arguments.contains("--snapshot") else { return }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "welcome")
        }
    }
}
