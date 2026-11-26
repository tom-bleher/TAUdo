import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, menuBar, moodle, courses, exams, notifications, calendar, updates

    /// Opens the Settings window on this tab.
    @MainActor func open(_ openSettings: OpenSettingsAction) {
        UserDefaults.standard.set(rawValue, forKey: "settingsTab")
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct SettingsView: View {
    static let width: CGFloat = 640

    @Environment(AppModel.self) private var model
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }.tag(SettingsTab.menuBar)
            MoodleSettings().tabItem { Label("Moodle", systemImage: "graduationcap") }.tag(SettingsTab.moodle)
            CoursesSettings().tabItem { Label("Courses", systemImage: "square.grid.3x3") }.tag(SettingsTab.courses)
            ExamsSettings().tabItem { Label("Exams", systemImage: "calendar.badge.clock") }.tag(SettingsTab.exams)
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell.badge") }.tag(SettingsTab.notifications)
            CalendarSettings().tabItem { Label("Calendar", systemImage: "calendar") }.tag(SettingsTab.calendar)
            UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.updates)
        }
        .frame(width: Self.width)
        // Reminders and the calendar follow the settings: one debounced push covers every control.
        .onChange(of: model.data.settings) { model.push() }
        // A new semester: keep its end after its start (a TAU semester is 13 weeks), and fetch its exam catalog.
        .onChange(of: model.data.settings.semesterStart) {
            let s = model.data.settings
            if s.semesterEnd < s.semesterStart { model.data.settings.semesterEnd = s.semesterStart.addingTimeInterval(13 * 7 * 86400) }
            model.refetchExams()
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var m = model
        Pane {
            Row("Startup") {
                Toggle("Open TAUdo at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do { try launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
            }
            Row("Language") {
                Picker("Language", selection: Binding(get: { Lang.code }, set: { Lang.set($0) })) {
                    Text(verbatim: "עברית").tag("he")
                    Text(verbatim: "English").tag("en")
                }
                .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
                Note("TAUdo restarts to switch language.")
            }
            Rule()
            Row("Semester") {
                HStack(spacing: 8) {
                    DatePicker("Starts", selection: $m.data.settings.semesterStart, displayedComponents: .date)
                    DatePicker("Ends", selection: $m.data.settings.semesterEnd, in: m.data.settings.semesterStart..., displayedComponents: .date)
                        .padding(.leading, 10)
                }
                .fixedSize()
                Note("These dates set where the class marker is in each course.")
            }
            Row("Self-study") {
                Toggle("Let courses be self-study", isOn: $m.data.settings.selfStudy)
                Note("Set per course under Courses: your own pace toward a finish date.")
            }
            Rule()
            Row("Data") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppModel.fileURL]) }
                Note("Everything TAUdo knows stays in one file on this Mac.")
            }
        }
    }
}

// MARK: Menu bar

struct MenuBarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Pane {
            Row("Menu Bar Shows") {
                Picker("Menu Bar Shows", selection: $m.data.settings.menuBar) {
                    Text("The icon only").tag(MenuBarContent.icon)
                    Text("Time left until the next deadline").tag(MenuBarContent.timeLeft)
                    Text("The next deadline and time left").tag(MenuBarContent.deadline)
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }
            Row("Missed") {
                Toggle("Show deadlines missed in the last week", isOn: $m.data.settings.showOverdue)
                Note("They head the list and are counted in the menu bar.")
            }
            Rule()
            Row("Deadline List") {
                Picker("Deadline List", selection: $m.data.settings.listLimit) {
                    ForEach([5, 8, 12, 20], id: \.self) { Text("\($0) deadlines").tag($0) }
                }
                .labelsHidden().fixedSize()
                Note("Later deadlines wait behind “more…”.")
            }
        }
    }
}

// MARK: Moodle

struct MoodleSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        let s = model.data.settings
        Pane {
            Row("Connection") {
                HStack(alignment: .firstTextBaseline) {
                    status
                    Spacer(minLength: 8)
                    Button("Refresh now") { Task { await model.refresh() } }.disabled(model.syncing || s.exportURL.isEmpty)
                }
            }
            Row("Calendar Link") {
                TextField("Calendar Link", text: $m.data.settings.exportURL, prompt: Text("https://moodle.tau.ac.il/…/calendar/export_execute.php?…"))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.refresh() } }
                Button("Connect in browser…") { model.connect() }
                Note("The link is a key to your Moodle calendar. Don't share it.")
            }
            Row("Refresh Every") {
                Picker("Refresh Every", selection: $m.data.settings.refreshMinutes) {
                    ForEach([15, 30, 60, 180], id: \.self) { m in Group { if m < 60 { Text("\(m) min") } else { Text("\(m / 60) h") } }.tag(m) }
                }
                .labelsHidden().fixedSize()
            }
            Rule()
            Row("Sync Bookmark") {
                HStack(alignment: .firstTextBaseline) {
                    Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: s.syncKey, base: s.moodleBaseURL) }
                    if let t = model.data.lastStatusCheck { Note(Text("Last used \(t.relative())")) }
                }
                Note("Click the bookmark on Moodle to mark the assignments you've submitted and find each course's Panopto recordings. On a course page it also downloads the course's files.")
            }
            Rule()
            Row("Course Files") {
                HStack {
                    TextField("Course Files", text: $m.data.settings.courseworkFolder, prompt: Text("Not set"))
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await model.scanFiles() } }
                    Button("Choose…") { if let p = FolderPicker.choose() { model.data.settings.courseworkFolder = p; Task { await model.scanFiles() } } }
                }
                Note("One subfolder per course, named like the course. Homework and recitation cubes then open their pset folder or notes (⌘-click or right-click).")
            }
            Rule()
            Row("Hidden") { hidden }
        }
    }

    @ViewBuilder private var status: some View {
        if let c = model.connectStatus { StatusLine(color: .blue, text: Text(c)) }
        else if let e = model.feedError { StatusLine(color: .orange, text: Text(e)) }
        else if model.data.settings.exportURL.isEmpty { StatusLine(color: .gray, text: Text("Not connected")) }
        else if let t = model.data.lastSync { StatusLine(color: .green, text: Text("Connected") + Text(verbatim: " · ") + Text("Synced \(t.relative())").foregroundStyle(.secondary)) }
        else { StatusLine(color: .gray, text: Text("Not synced yet")) }
    }

    /// Courses and deadlines you said aren't yours, with a way back.
    @ViewBuilder private var hidden: some View {
        let keys = model.data.ignoredCourseKeys.sorted()
        if keys.isEmpty && model.hiddenDeadlineCount == 0 {
            Text("Nothing is hidden.").foregroundStyle(.secondary)
        }
        ForEach(keys, id: \.self) { key in
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: key).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Show again") { model.show(moodleCourse: key) }.controlSize(.small)
            }
        }
        if model.hiddenDeadlineCount > 0 {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.hiddenDeadlineCount) hidden deadlines")
                Spacer(minLength: 8)
                Button("Show again") { model.showHiddenDeadlines() }.controlSize(.small)
            }
        }
        if !keys.isEmpty { Note("Deadlines of hidden courses stay out of the list, the reminders and the calendar.") }
    }
}

// MARK: Notifications

struct NotificationSettings: View {
    @Environment(AppModel.self) private var model
    /// Whether macOS allows TAUdo's notifications (nil: not asked yet).
    @State private var allowed: Bool?
    @State private var lastDigestHour = 8

    private static let reminderChoices: [(Int, String)] = [
        (7 * 1440, String(localized: "1 week")), (2 * 1440, String(localized: "2 days")), (1440, String(localized: "1 day")),
        (180, String(localized: "3 hours")), (60, String(localized: "1 hour")),
    ]

    var body: some View {
        @Bindable var m = model
        let s = model.data.settings
        Pane {
            Row("Notify With") {
                Toggle("Mac notifications", isOn: $m.data.settings.notifications)
                    .onChange(of: s.notifications) {
                        // Push again once the system prompt is answered: reminders can't be scheduled before that.
                        Task { if s.notifications { _ = await Notifier.requestAuthorization() }; allowed = await Notifier.isAllowed(); model.push() }
                    }
                if s.notifications && allowed == false {
                    HStack(alignment: .firstTextBaseline) {
                        StatusLine(color: .orange, text: Text("Notifications from TAUdo are turned off in System Settings."))
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                        .controlSize(.small)
                    }
                    .font(.callout)
                }
            }
            Row("Remind Me Before") {
                HStack(spacing: 14) {
                    ForEach(Self.reminderChoices, id: \.0) { minutes, label in
                        Toggle(label, isOn: Binding(
                            get: { s.reminderMinutes.contains(minutes) },
                            set: { on in
                                var r = Set(s.reminderMinutes)
                                if on { r.insert(minutes) } else { r.remove(minutes) }
                                model.data.settings.reminderMinutes = r.sorted(by: >)
                            }))
                    }
                }
                Note(s.calendarSync ? "With calendar sync on, these are calendar alerts, so they reach your iPhone too."
                                    : "Deadlines you've marked done never remind you.")
            }
            // Calendar alerts use these lead times too, with or without Mac notifications.
            .disabled(!s.notifications && !s.calendarSync)
            Group {
                Row("Also Notify") {
                    Toggle("When Moodle posts or moves a deadline", isOn: $m.data.settings.alertChanges)
                    HStack(spacing: 6) {
                        Toggle("With a morning summary at", isOn: Binding(get: { s.digestHour != nil },
                                                                          set: { model.data.settings.digestHour = $0 ? lastDigestHour : nil }))
                        Picker("Morning summary", selection: Binding(get: { s.digestHour ?? lastDigestHour },
                                                                     set: { lastDigestHour = $0; model.data.settings.digestHour = $0 })) {
                            ForEach([6, 7, 8, 9, 10], id: \.self) { h in Text(verbatim: String(format: "%02d:00", h)).tag(h) }
                        }
                        .labelsHidden().fixedSize().disabled(s.digestHour == nil)
                    }
                }
                Rule()
                Row("Options") {
                    Toggle("Play a sound", isOn: $m.data.settings.notificationSound)
                    Button("Send Test Notification") {
                        Notifier.sound = s.notificationSound
                        Notifier.post(String(localized: "TAUdo notifications work"), String(localized: "This is how a reminder looks."), id: "test")
                    }
                }
            }
            .disabled(!s.notifications)
        }
        .task { allowed = await Notifier.isAllowed(); lastDigestHour = s.digestHour ?? 8 }
    }
}

// MARK: Calendar

struct CalendarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        let s = model.data.settings
        Pane {
            Row("Calendar Sync") {
                Toggle("Mirror Moodle into a calendar", isOn: $m.data.settings.calendarSync)
                Note("Each deadline becomes an all-day event with its due time and a done mark, in Apple Calendar or any account your Mac syncs.")
            }
            Group {
                Row("Calendar") {
                    Picker("Calendar", selection: Binding(get: { s.calendarID }, set: { model.useCalendar($0) })) {
                        Text("New calendar “\(s.calendarName)”").tag(String?.none)
                        // Chosen calendar not listed (no calendar access right now): keep the selection valid.
                        if let id = s.calendarID, !model.calendarChoices.contains(where: { $0.id == id }) {
                            Text(verbatim: s.calendarName).tag(Optional(id))
                        }
                        ForEach(Dictionary(grouping: model.calendarChoices, by: \.account).sorted { $0.key < $1.key }, id: \.key) { account, calendars in
                            Section(account) {
                                ForEach(calendars, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                            }
                        }
                    }
                    .labelsHidden().fixedSize()
                    if s.calendarSync, let status = model.calendarStatus { Note(Text(status)) }
                }
                Row("Include") {
                    Toggle("Lectures and other Moodle events, not only deadlines", isOn: $m.data.settings.calendarIncludesAllEvents)
                }
            }
            .disabled(!s.calendarSync)
            Rule()
            Row("Google Calendar") {
                Button("Add Google Account…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                }
                Note("Add your Google account in System Settings › Internet Accounts with Calendars on, then pick one of its calendars above. TAUdo writes to it like any other calendar: all-day deadlines, done marks and alerts. To keep them apart, first create a calendar named Moodle in Google Calendar.")
            }
        }
        .onAppear { model.refreshCalendarChoices() }
    }
}

// MARK: Updates

struct UpdateSettings: View {
    @Bindable private var updates = Updates.shared

    var body: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        Pane {
            Row("Check for Updates") {
                Toggle("Automatically", isOn: $updates.checksAutomatically)
                Toggle("Download and install new versions automatically", isOn: $updates.installsAutomatically)
                    .disabled(!updates.checksAutomatically)
                Button("Check Now") { updates.check() }.disabled(!updates.canCheck)
                Note("Updates install when TAUdo quits.")
            }
            Rule()
            Row("Version") {
                Text(verbatim: "TAUdo \(version)").textSelection(.enabled)
                Link("TAUdo on GitHub", destination: URL(string: "https://github.com/tom-bleher/TAUdo")!).font(.callout)
            }
        }
    }
}

// MARK: Courses

/// Courses on one side, the selected course's details on the other.
struct CoursesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var deleting: Course?

    /// Moodle courses seen in the feed. Shown with their course code, which tells same-named courses apart.
    private var moodleCourses: [String] { Set(model.data.events.compactMap(\.courseKey)).sorted() }

    private var selected: UUID? { selection ?? model.data.courses.first?.id }

    var body: some View {
        @Bindable var m = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List {
                    ForEach(model.data.courses) { c in
                        HStack(spacing: 8) {
                            Circle().fill(Palette.course(model.data.courses.firstIndex { $0.id == c.id })).frame(width: 8, height: 8)
                            Text(c.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = c.id }
                        .accessibilityAddTraits(c.id == selected ? [.isButton, .isSelected] : .isButton)
                        .listRowSeparator(.hidden)
                        .listRowBackground(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(c.id == selected ? 0.2 : 0)).padding(.horizontal, 6))
                    }
                    .onMove { model.data.courses.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).padding(.top, 6)
                Divider()
                HStack(spacing: 2) {
                    Button {
                        let c = Course.standard(String(localized: "New course"))
                        model.data.courses.append(c); selection = c.id
                    } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                        .help(Text("Add course"))
                    Button { deleting = model.data.courses.first { $0.id == selected } } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                        .disabled(selected == nil).help(Text("Delete course"))
                    Spacer()
                }
                .buttonStyle(.borderless).padding(4)
            }
            .frame(width: 180)
            .background(Color.primary.opacity(0.03))
            Divider()
            if let i = model.data.courses.firstIndex(where: { $0.id == selected }) {
                detail($m.data.courses[i])
            } else {
                Text("No courses yet. Connect Moodle and pick your courses, or add one in Settings.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: SettingsView.width, height: 430)
        // Names, Moodle links and rows show up in reminders and the calendar.
        .onChange(of: model.data.courses) { model.push() }
        .confirmationDialog(Text("Delete “\(deleting?.name ?? "")”?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete course", role: .destructive) {
                model.data.courses.removeAll { $0.id == deleting?.id }
                selection = nil
            }
        } message: { Text("Its progress cubes are deleted too. Moodle deadlines stay.") }
    }

    private func detail(_ course: Binding<Course>) -> some View {
        let c = course.wrappedValue
        return ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                field("Name") { TextField("Name", text: course.name).labelsHidden().textFieldStyle(.roundedBorder) }
                field("Moodle Course") {
                    Picker("Moodle Course", selection: course.moodleKey) {
                        Text("None").tag(String?.none)
                        ForEach(moodleCourses, id: \.self) { Text(verbatim: $0).tag(Optional($0)) }
                        if let k = c.moodleKey, !moodleCourses.contains(k) { Text(verbatim: k).tag(Optional(k)) }
                    }
                    .labelsHidden()
                }
                if model.data.settings.selfStudy { field("Pace") {
                    Picker("Pace", selection: course.pace) {
                        ForEach(Pace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
                    if c.pace == .selfStudy {
                        DatePicker("Finish by", selection: Binding(get: { c.targetDate ?? model.data.settings.semesterEnd },
                                                                   set: { course.wrappedValue.targetDate = $0 }), displayedComponents: .date)
                            .fixedSize()
                    }
                } }
                field("Folder") {
                    HStack {
                        TextField("Folder", text: Binding(get: { c.folder ?? "" }, set: { course.wrappedValue.folder = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(model.data.settings.courseworkFolder.isEmpty ? "" : (model.data.settings.courseworkFolder as NSString).appendingPathComponent(c.name)))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await model.scanFiles() } }
                        Button("Choose…") { if let p = FolderPicker.choose() { course.wrappedValue.folder = p; Task { await model.scanFiles() } } }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 2)
                // The rows table needs the full width, so it sits under its heading instead of beside it.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rows").fontWeight(.semibold)
                    rows(course)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
    }

    private func field<C: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        GridRow {
            Text(label).fontWeight(.semibold).gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 7) { content() }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func rows(_ course: Binding<Course>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: Col.gap) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Type").frame(width: Col.type, alignment: .leading)
                Text("Items").frame(width: Col.number, alignment: .leading)
                Text("Per week").frame(width: Col.number, alignment: .leading)
                Color.clear.frame(width: Col.remove, height: 1)
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach(course.tracks) { $t in
                HStack(spacing: Col.gap) {
                    TextField("Row", text: $t.name).labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    Picker("Type", selection: $t.kind) { ForEach(TrackKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: Col.type, alignment: .leading)
                    number($t.count, in: 0...60)
                    number($t.perWeek, in: 0...7).help(Text("Class sessions per week, to estimate where the class is"))
                    Button { course.wrappedValue.tracks.removeAll { $0.id == t.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).frame(width: Col.remove)
                }
            }
        }
        Button("Add row") { course.wrappedValue.tracks.append(Track(name: String(localized: "Row"), kind: .other, count: 13, perWeek: 1)) }
        Note("⌥-click a cube in the menu bar panel to say where the class is now. The class keeps advancing from there.")
    }
}

private enum Col {
    static let gap: CGFloat = 8, type: CGFloat = 104, number: CGFloat = 58, remove: CGFloat = 18
}

/// A number with a stepper, sized for a table column.
private func number(_ value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
    HStack(spacing: 4) {
        Text(verbatim: "\(value.wrappedValue)").monospacedDigit().frame(minWidth: 20, alignment: .trailing)
        Stepper("", value: value, in: range).labelsHidden()
    }
    .frame(width: Col.number, alignment: .leading)
}

// MARK: Exams

struct ExamsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Pane {
            Row("Exam Dates") {
                Toggle("Add exam dates from Arazim", isOn: $m.data.settings.fetchExams)
                Note("From the public course list at arazim-project.com, once a day. Nothing about you is sent.")
            }
            Row("Show") {
                Toggle("Also list exams under Deadlines and in the menu bar", isOn: $m.data.settings.examsWithDeadlines)
                Note("They always have their own tab. Reminders and the calendar include them either way.")
            }
            Rule()
            Row("My Own") {
                ForEach($m.data.manual) { $x in
                    HStack {
                        TextField("Title", text: $x.title, prompt: Text("Title")).labelsHidden().textFieldStyle(.roundedBorder)
                        Picker("Courses", selection: $x.courseID) {
                            Text("No course").tag(UUID?.none)
                            ForEach(model.data.courses) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden().frame(width: 116)
                        DatePicker("Due", selection: $x.due).labelsHidden().fixedSize()
                        Button { model.data.manual.removeAll { $0.id == x.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                Button("Add exam or deadline") {
                    model.addDeadline(title: String(localized: "Exam"), due: ManualDeadline.suggestedDue(), courseID: model.data.courses.first?.id)
                }
                Note("Exams and deadlines that aren't on Moodle. They show up in the panel, the reminders and the calendar like Moodle deadlines.")
            }
        }
        .onChange(of: model.data.manual) { model.push() }
        // Turned on: fetch the dates now instead of at the next hourly refresh.
        .onChange(of: model.data.settings.fetchExams) { if model.data.settings.fetchExams { model.refetchExams() } }
    }
}
