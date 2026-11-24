import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let width: CGFloat = 640

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            MoodleSettings().tabItem { Label("Moodle", systemImage: "link") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell.badge") }
            CoursesSettings().tabItem { Label("Courses", systemImage: "square.grid.3x3") }
            ExamsSettings().tabItem { Label("Exams", systemImage: "calendar.badge.plus") }
        }
        .frame(width: Self.width)
    }
}

private extension View {
    /// A grouped settings form as tall as its content, so each tab gets a window that fits it.
    func settingsForm() -> some View {
        formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }

    func footnote() -> some View { font(.caption).foregroundStyle(.secondary) }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                Toggle("Show the next deadline and days left", isOn: $m.data.settings.menuBarShowsNext)
                Toggle("Show overdue deadlines", isOn: $m.data.settings.showOverdue)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do { try launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Menu bar") }
            Section {
                DatePicker("Starts", selection: $m.data.settings.semesterStart, displayedComponents: .date)
                DatePicker("Ends", selection: $m.data.settings.semesterEnd, displayedComponents: .date)
            } header: { Text("Semester") } footer: {
                Text("These dates set where the class marker is in each course.").footnote()
            }
            Section {
                Picker("Language", selection: Binding(get: { Lang.code }, set: { Lang.set($0) })) {
                    Text(verbatim: "עברית").tag("he")
                    Text(verbatim: "English").tag("en")
                }
            } footer: { Text("TAUdo restarts to switch language.").footnote() }
        }
        .settingsForm()
    }
}

struct MoodleSettings: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                TextField("Calendar export link", text: $m.data.settings.exportURL, prompt: Text("https://moodle.tau.ac.il/…/calendar/export_execute.php?…"))
                    .onSubmit { Task { await model.refresh() } }
                Picker("Refresh every", selection: $m.data.settings.refreshMinutes) {
                    ForEach([15, 30, 60, 180], id: \.self) { m in Group { if m < 60 { Text("\(m) min") } else { Text("\(m / 60) h") } }.tag(m) }
                }
                HStack {
                    Group {
                        if let s = model.connectStatus { Text(s).foregroundStyle(.blue) }
                        else if let e = model.feedError { Text(e).foregroundStyle(.orange) }
                        else if let t = model.data.lastSync { Text("Synced \(t.relative())").foregroundStyle(.secondary) }
                        else { Text("Not synced yet").foregroundStyle(.secondary) }
                    }
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Connect in browser…") { model.connect() }
                    Button("Refresh now") { Task { await model.refresh() } }.disabled(model.syncing)
                }
            } header: { Text("Deadlines") }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync bookmark")
                        if let t = model.data.lastStatusCheck { Text("Last used \(t.relative())").footnote() }
                    }
                    Spacer(minLength: 8)
                    Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
                }
            } footer: {
                Text("Click the bookmark on Moodle to mark the assignments you've submitted. On a course page it also downloads the course's files.").footnote()
            }
            Section {
                HStack {
                    TextField("Coursework folder", text: $m.data.settings.courseworkFolder, prompt: Text("Not set"))
                        .onSubmit { Task { await model.scanFiles() } }
                    Button("Choose…") { if let p = FolderPicker.choose() { model.data.settings.courseworkFolder = p; Task { await model.scanFiles() } } }
                }
            } header: { Text("Files") } footer: {
                Text("One subfolder per course, named like the course. Cubes then open their lecture video, pset folder or recitation (⌘-click or right-click).").footnote()
            }
            if !model.data.ignoredCourseKeys.isEmpty {
                Section("Hidden Moodle courses") {
                    ForEach(model.data.ignoredCourseKeys.sorted(), id: \.self) { key in
                        HStack {
                            Text(model.data.courseLabel(key))
                            Spacer()
                            Button("Show again") { model.data.ignoredCourseKeys.remove(key); model.push() }
                        }
                    }
                }
            }
            Section {
                Button("Import progress from track.html…") { importing = true }
            }
        }
        .settingsForm()
        .sheet(isPresented: $importing) { ImportSheet() }
    }
}

struct NotificationSettings: View {
    @Environment(AppModel.self) private var model

    private static let reminderChoices: [(Int, String)] = [
        (7 * 1440, String(localized: "1 week")), (2 * 1440, String(localized: "2 days")), (1440, String(localized: "1 day")),
        (180, String(localized: "3 hours")), (60, String(localized: "1 hour")),
    ]

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                Toggle("Mac notifications", isOn: $m.data.settings.notifications)
                    .onChange(of: model.data.settings.notifications) {
                        Task { if model.data.settings.notifications { _ = await Notifier.requestAuthorization() }; model.push() }
                    }
                LabeledContent("Remind me before a deadline") {
                    HStack(spacing: 4) {
                        ForEach(Self.reminderChoices, id: \.0) { minutes, label in
                            Toggle(label, isOn: Binding(
                                get: { model.data.settings.reminderMinutes.contains(minutes) },
                                set: { on in
                                    var r = Set(model.data.settings.reminderMinutes)
                                    if on { r.insert(minutes) } else { r.remove(minutes) }
                                    model.data.settings.reminderMinutes = r.sorted(by: >)
                                    model.push()
                                }))
                            .toggleStyle(.button)
                        }
                    }
                    .controlSize(.small)
                }
                Toggle("Alert when Moodle posts or moves a deadline", isOn: $m.data.settings.alertChanges)
                Picker("Morning summary", selection: Binding(get: { model.data.settings.digestHour ?? -1 },
                                                             set: { model.data.settings.digestHour = $0 < 0 ? nil : $0; model.push() })) {
                    Text("Off").tag(-1)
                    ForEach([6, 7, 8, 9, 10], id: \.self) { h in Text(verbatim: String(format: "%02d:00", h)).tag(h) }
                }
            } footer: { Text("Deadlines you've marked done never remind you.").footnote() }
            Section {
                Toggle("Mirror Moodle into a calendar", isOn: $m.data.settings.calendarSync)
                    .onChange(of: model.data.settings.calendarSync) { model.push() }
                if model.data.settings.calendarSync {
                    if !model.calendarChoices.isEmpty {
                        Picker("Calendar", selection: Binding(get: { model.data.settings.calendarID }, set: { model.useCalendar($0) })) {
                            Text("New calendar “\(model.data.settings.calendarName)”").tag(String?.none)
                            ForEach(Dictionary(grouping: model.calendarChoices, by: \.account).sorted { $0.key < $1.key }, id: \.key) { account, calendars in
                                Section(account) {
                                    ForEach(calendars, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                                }
                            }
                        }
                    }
                    Toggle("Include lectures and other events, not only deadlines", isOn: $m.data.settings.calendarIncludesAllEvents)
                        .onChange(of: model.data.settings.calendarIncludesAllEvents) { model.push() }
                    if let s = model.calendarStatus { Text(s).footnote() }
                }
            } header: { Text("Calendar") } footer: {
                Text("With mirroring on, reminders are calendar alerts instead of Mac notifications, so they reach your iPhone too.").footnote()
            }
            Section {
                HStack {
                    Text("Google Calendar")
                    Spacer(minLength: 8)
                    Button("Subscribe in Google Calendar…") { model.subscribeInGoogleCalendar() }
                        .disabled(model.data.settings.exportURL.isEmpty)
                }
            } footer: {
                Text("Best: add your Google account in System Settings › Internet Accounts, then pick one of its calendars above. TAUdo then writes to Google directly, with done marks and alerts. Or subscribe Google Calendar to your Moodle link: it shows Moodle's own titles and Google refreshes it only every few hours.").footnote()
            }
        }
        .settingsForm()
        .onAppear { model.refreshCalendarChoices() }
    }
}

struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import from track.html").font(.headline)
            Text("Open track.html in your browser, open the developer console and run:").font(.callout)
            Text("copy(localStorage['course-tracker-v1'])").font(.callout.monospaced()).textSelection(.enabled)
            Text("Then paste here. This replaces your courses.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.caption.monospaced()).frame(height: 180).border(.separator)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    do {
                        var imported = try AppData.importTrackHTML(text)
                        // Keep Moodle mappings and pace for courses with the same name.
                        for i in imported.indices {
                            if let old = model.data.courses.first(where: { $0.name == imported[i].name }) {
                                imported[i].moodleKey = old.moodleKey; imported[i].pace = old.pace; imported[i].targetDate = old.targetDate
                            }
                        }
                        model.data.courses = imported
                        model.push()
                        dismiss()
                    } catch { self.error = String(localized: "Couldn't read that: \(error.localizedDescription)") }
                }
                .keyboardShortcut(.defaultAction).disabled(text.isEmpty)
            }
        }
        .padding(20).frame(width: 480)
    }
}

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
            .frame(width: 190)
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
        .frame(height: 500)
        .confirmationDialog(Text("Delete “\(deleting?.name ?? "")”?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete course", role: .destructive) {
                model.data.courses.removeAll { $0.id == deleting?.id }
                selection = nil
            }
        } message: { Text("Its progress cubes are deleted too. Moodle deadlines stay.") }
    }

    private func detail(_ course: Binding<Course>) -> some View {
        let c = course.wrappedValue
        return Form {
            Section {
                TextField("Name", text: course.name)
                Picker("Moodle course", selection: course.moodleKey) {
                    Text("None").tag(String?.none)
                    ForEach(moodleCourses, id: \.self) { Text(verbatim: $0).tag(Optional($0)) }
                    if let k = c.moodleKey, !moodleCourses.contains(k) { Text(verbatim: k).tag(Optional(k)) }
                }
                Picker("Pace", selection: course.pace) {
                    ForEach(Pace.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if c.pace == .selfStudy {
                    DatePicker("Finish by", selection: Binding(get: { c.targetDate ?? model.data.settings.semesterEnd },
                                                               set: { course.wrappedValue.targetDate = $0 }), displayedComponents: .date)
                }
            }
            Section {
                VStack(spacing: 8) {
                    HStack(spacing: Col.gap) {
                        Text("Row").frame(maxWidth: .infinity, alignment: .leading)
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
            } header: { Text("Rows") } footer: {
                Text("⌥-click a cube in the menu bar panel to say where the class is now. The class keeps advancing from there.").footnote()
            }
            Section {
                HStack {
                    TextField("Folder", text: Binding(get: { c.folder ?? "" }, set: { course.wrappedValue.folder = $0.isEmpty ? nil : $0 }),
                              prompt: Text(model.data.settings.courseworkFolder.isEmpty ? "" : (model.data.settings.courseworkFolder as NSString).appendingPathComponent(c.name)))
                        .onSubmit { Task { await model.scanFiles() } }
                    Button("Choose…") { if let p = FolderPicker.choose() { course.wrappedValue.folder = p; Task { await model.scanFiles() } } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private enum Col {
    static let gap: CGFloat = 10, type: CGFloat = 112, number: CGFloat = 62, remove: CGFloat = 18
}

/// A number with a stepper, sized for a table column.
private func number(_ value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
    HStack(spacing: 4) {
        Text(verbatim: "\(value.wrappedValue)").monospacedDigit().frame(minWidth: 20, alignment: .trailing)
        Stepper("", value: value, in: range).labelsHidden()
    }
    .frame(width: Col.number, alignment: .leading)
}

struct ExamsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                ForEach($m.data.manual) { $x in
                    HStack {
                        TextField("Title", text: $x.title, prompt: Text("Title")).labelsHidden().textFieldStyle(.roundedBorder)
                        Picker("Courses", selection: $x.courseID) {
                            Text("No course").tag(UUID?.none)
                            ForEach(model.data.courses) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden().frame(width: 170)
                        DatePicker("Due", selection: $x.due).labelsHidden()
                        Button { model.data.manual.removeAll { $0.id == x.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                Button("Add exam or deadline") {
                    model.data.manual.append(ManualDeadline(title: String(localized: "Exam"), due: Calendar.current.startOfDay(for: .now).addingTimeInterval(14 * 86400 + 9 * 3600), courseID: model.data.courses.first?.id))
                }
            } footer: {
                Text("For exams and deadlines that aren't on Moodle. They show up in the menu bar, reminders and the calendar like Moodle deadlines.").footnote()
            }
        }
        .settingsForm()
        .onChange(of: model.data.manual) { model.push() }
    }
}
