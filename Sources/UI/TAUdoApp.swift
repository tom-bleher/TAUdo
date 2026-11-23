import AppKit
import SwiftUI
import UserNotifications

@main
struct TAUdoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { AppDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings { SettingsView().environment(model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// `--demo` uses sample Moodle data in memory and never touches your saved state.
    @MainActor static let model: AppModel = CommandLine.arguments.contains("--demo") ? AppModel(data: Demo.data(now: .now), persist: false) : AppModel()
    private var previewWindow: NSWindow?

    /// "Mark done" on a reminder.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
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

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let overdue = model.overdueCount
        if model.data.settings.menuBarShowsNext, let next = model.next {
            Image(nsImage: Logo.menuBarImage)
            Text((overdue > 0 ? "\(overdue) overdue · " : "") + model.menuTitle(next))
        } else if overdue > 0 {
            Image(nsImage: Logo.menuBarImage)
            Text("\(overdue) overdue")
        } else {
            Image(nsImage: Logo.menuBarImage)
        }
    }
}
