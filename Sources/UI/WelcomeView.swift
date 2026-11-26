import AppKit
import ServiceManagement
import SwiftUI

/// First-run setup: connect Moodle, pick courses, optionally a coursework folder and notifications.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @State private var picked: Set<String> = []
    @State private var notificationsAsked = false
    @State private var openAtLogin = true

    var body: some View {
        let connected = !model.data.settings.exportURL.isEmpty
        let keys = model.data.moodleCourseKeys.filter { k in !model.data.courses.contains { $0.moodleKey == k } }
        let needsCourses = connected && model.data.courses.isEmpty && !keys.isEmpty
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to TAUdo").font(.title2.weight(.semibold))
                    Text("Your Moodle deadlines and course progress, in the menu bar.").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                step(1, done: connected && model.feedError == nil && model.data.lastSync != nil, title: "Connect Moodle") {
                    if connected && model.syncing && model.data.lastSync == nil {
                        Text("Syncing…").foregroundStyle(.secondary)
                    } else if connected, let error = model.feedError {
                        // The link didn't work: say why, and offer to connect again.
                        Text(model.connectStatus ?? error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Button("Open Moodle in browser") { model.connect() }.buttonStyle(.borderedProminent)
                    } else if connected {
                        Text("Connected. Deadlines sync on their own.").foregroundStyle(.secondary)
                    } else {
                        Text(model.connectStatus ?? String(localized: "Log in to Moodle in your browser and copy your calendar link. TAUdo picks it up from the clipboard."))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Open Moodle in browser") { model.connect() }.buttonStyle(.borderedProminent)
                    }
                }
                Divider().padding(.leading, 50)
                step(2, done: !model.data.courses.isEmpty, title: "Choose your courses") {
                    if !connected && model.data.courses.isEmpty {
                        Text("Your Moodle courses appear here once Moodle is connected.").foregroundStyle(.secondary)
                    } else if keys.isEmpty {
                        Text(model.data.courses.isEmpty ? String(localized: "No Moodle courses with deadlines yet. You can add courses in Settings.")
                                                        : String(localized: "\(model.data.courses.count) courses are tracked."))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(keys, id: \.self) { key in
                                Toggle(model.data.courseLabel(key), isOn: Binding(
                                    get: { picked.contains(key) }, set: { if $0 { picked.insert(key) } else { picked.remove(key) } }))
                            }
                        }
                        if needsCourses { track(keys).buttonStyle(.borderedProminent) } else { track(keys) }
                    }
                }
                Divider().padding(.leading, 50)
                step(3, done: !model.data.settings.courseworkFolder.isEmpty, title: "Course folder (optional)") {
                    Text("If you keep one folder per course, cubes can open your homework folders and recitation notes.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Choose folder…") { if let p = FolderPicker.choose() { model.data.settings.courseworkFolder = p; Task { await model.scanFiles() } } }
                        if !model.data.settings.courseworkFolder.isEmpty {
                            Text(model.data.settings.courseworkFolder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Divider().padding(.leading, 50)
                step(4, done: notificationsAsked, title: "Reminders") {
                    Text("TAUdo reminds you a day and a few hours before each open deadline.").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !notificationsAsked {
                        Button("Allow notifications") {
                            Task { _ = await Notifier.requestAuthorization(); notificationsAsked = true; model.push() }
                        }
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Open TAUdo at login", isOn: $openAtLogin)
                    Text("TAUdo lives in the menu bar. Everything here can be changed later in Settings.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Done") {
                    if openAtLogin { try? SMAppService.mainApp.register() }
                    model.finishOnboarding(); onDone()
                }
                .keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { picked = Set(model.data.moodleCourseKeys) }
        .onChange(of: model.data.moodleCourseKeys) { picked.formUnion(model.data.moodleCourseKeys) }
    }

    private func track(_ keys: [String]) -> some View {
        Button("Track selected courses") {
            for k in keys where picked.contains(k) { model.addCourse(fromMoodle: k) }
        }
        .disabled(picked.isDisjoint(with: keys))
    }

    private func step<C: View>(_ n: Int, done: Bool, title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                else { Text(verbatim: "\(n)").font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).frame(minHeight: 24)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

enum FolderPicker {
    /// Asks for a folder; returns its path with ~ for the home folder.
    @MainActor static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}
