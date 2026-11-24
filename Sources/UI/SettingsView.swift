import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CoursesSettings().tabItem { Label("Courses", systemImage: "square.grid.3x3") }
            ExamsSettings().tabItem { Label("Exams", systemImage: "pencil.and.list.clipboard") }
        }
        .frame(width: 560, height: 600)
    }
}

private let reminderChoices: [(Int, String)] = [
    (7 * 1440, String(localized: "1 week before")), (2 * 1440, String(localized: "2 days before")), (1440, String(localized: "1 day before")),
    (180, String(localized: "3 hours before")), (60, String(localized: "1 hour before")),
]

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var m = model
        Form {
            Section("Moodle") {
                TextField("Calendar export link", text: $m.data.settings.exportURL, prompt: Text("https://moodle.tau.ac.il/…/calendar/export_execute.php?…"))
                    .onSubmit { Task { await model.refresh() } }
                HStack {
                    Button("Connect in browser…") { model.connect() }
                    Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
                    Button("Refresh now") { Task { await model.refresh() } }.disabled(model.syncing)
                }
                if let s = model.connectStatus { Text(s).font(.caption).foregroundStyle(.blue) }
                if let t = model.data.lastSync { Text("Deadlines synced \(t.relative()). They refresh on their own.").font(.caption).foregroundStyle(.secondary) }
                if let e = model.feedError { Text(e).foregroundStyle(.orange) }
                Group {
                    if let t = model.data.lastStatusCheck { Text("Submitted assignments: click the TAUdo sync bookmark on Moodle (last used \(t.relative())).") }
                    else { Text("Submitted assignments: click the TAUdo sync bookmark on Moodle.") }
                }
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Refresh every", selection: $m.data.settings.refreshMinutes) {
                    ForEach([15, 30, 60, 180], id: \.self) { m in Group { if m < 60 { Text("\(m) min") } else { Text("\(m / 60) h") } }.tag(m) }
                }
            }
            Section {
                HStack {
                    TextField("Coursework folder", text: $m.data.settings.courseworkFolder, prompt: Text("Not set"))
                        .onSubmit { Task { await model.scanFiles() } }
                    Button("Choose…") { if let p = FolderPicker.choose() { model.data.settings.courseworkFolder = p; Task { await model.scanFiles() } } }
                }
            } header: { Text("Files") } footer: {
                Text("One subfolder per course, named like the course. Cubes then open their lecture video, pset folder or recitation (⌘-click or right-click).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Semester") {
                DatePicker("Starts", selection: $m.data.settings.semesterStart, displayedComponents: .date)
                DatePicker("Ends", selection: $m.data.settings.semesterEnd, displayedComponents: .date)
            }
            Section("Apple Calendar") {
                Toggle("Mirror Moodle into a calendar", isOn: $m.data.settings.calendarSync)
                    .onChange(of: model.data.settings.calendarSync) { model.push() }
                TextField("Calendar name", text: $m.data.settings.calendarName).onSubmit { model.push() }
                Toggle("Include lectures and other events, not only deadlines", isOn: $m.data.settings.calendarIncludesAllEvents)
                    .onChange(of: model.data.settings.calendarIncludesAllEvents) { model.push() }
                if let s = model.calendarStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(reminderChoices, id: \.0) { minutes, label in
                    Toggle(label, isOn: Binding(
                        get: { model.data.settings.reminderMinutes.contains(minutes) },
                        set: { on in
                            var r = Set(model.data.settings.reminderMinutes)
                            if on { r.insert(minutes) } else { r.remove(minutes) }
                            model.data.settings.reminderMinutes = r.sorted(by: >)
                            model.push()
                        }))
                }
                Toggle("Alert when Moodle posts or moves a deadline", isOn: $m.data.settings.alertChanges)
                Picker("Morning summary", selection: Binding(get: { model.data.settings.digestHour ?? -1 },
                                                             set: { model.data.settings.digestHour = $0 < 0 ? nil : $0; model.push() })) {
                    Text("Off").tag(-1)
                    ForEach([6, 7, 8, 9, 10], id: \.self) { h in Text(verbatim: String(format: "%02d:00", h)).tag(h) }
                }
                Toggle("Mac notifications", isOn: $m.data.settings.notifications)
                    .onChange(of: model.data.settings.notifications) {
                        Task { if model.data.settings.notifications { _ = await Notifier.requestAuthorization() }; model.push() }
                    }
            } header: { Text("Reminders for open deadlines") } footer: {
                Text("With calendar mirroring on, reminders are calendar alerts (they reach your iPhone too) instead of Mac notifications. Done deadlines never remind you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Language", selection: Binding(get: { Lang.code }, set: { Lang.set($0) })) {
                    Text(verbatim: "עברית").tag("he")
                    Text(verbatim: "English").tag("en")
                }
                Text("TAUdo restarts to switch language.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Show the next deadline and days left", isOn: $m.data.settings.menuBarShowsNext)
                Toggle("Show overdue deadlines", isOn: $m.data.settings.showOverdue)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do { try launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
            }
            Section("Import") {
                Button("Import progress from track.html…") { importing = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $importing) { ImportSheet() }
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

struct CoursesSettings: View {
    @Environment(AppModel.self) private var model

    /// Moodle courses seen in the feed, with an example title so the shortnames are recognisable.
    private var moodleCourses: [(key: String, sample: String)] {
        var seen: [String: String] = [:]
        for e in model.data.events { if let k = e.courseKey, seen[k] == nil { seen[k] = model.data.moodleCourseNames[k] ?? Classifier.cleanTitle(e.summary) } }
        return seen.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        @Bindable var m = model
        Form {
            ForEach($m.data.courses) { $course in
                Section {
                    TextField("Name", text: $course.name)
                    HStack {
                        TextField("Folder", text: Binding(get: { course.folder ?? "" }, set: { course.folder = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(model.data.settings.courseworkFolder.isEmpty ? "" : (model.data.settings.courseworkFolder as NSString).appendingPathComponent(course.name)))
                        Button("Choose…") { if let p = FolderPicker.choose() { course.folder = p; Task { await model.scanFiles() } } }
                    }
                    Picker("Moodle course", selection: $course.moodleKey) {
                        Text("None").tag(String?.none)
                        ForEach(moodleCourses, id: \.key) { Text("\($0.key) — \($0.sample)").tag(Optional($0.key)) }
                        if let k = course.moodleKey, !moodleCourses.contains(where: { $0.key == k }) { Text(k).tag(Optional(k)) }
                    }
                    Picker("Pace", selection: $course.pace) {
                        ForEach(Pace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if course.pace == .selfStudy {
                        DatePicker("Finish by", selection: Binding(get: { course.targetDate ?? model.data.settings.semesterEnd },
                                                                   set: { course.targetDate = $0 }), displayedComponents: .date)
                    }
                    ForEach($course.tracks) { $t in
                        HStack {
                            TextField("Row", text: $t.name).labelsHidden().frame(width: 100)
                            Picker("", selection: $t.kind) { ForEach(TrackKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                                .labelsHidden().frame(width: 110)
                            Stepper("\(t.count) items", value: $t.count, in: 0...60)
                            Stepper("\(t.perWeek)/wk", value: $t.perWeek, in: 0...7).help("Class sessions per week, to estimate where the class is")
                            Button { course.tracks.removeAll { $0.id == t.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button("Add row") { course.tracks.append(Track(name: String(localized: "Row"), kind: .other, count: 13, perWeek: 1)) }
                        Spacer()
                        Button("Move up") { move(course.id, -1) }.disabled(model.data.courses.first?.id == course.id)
                        Button("Delete course", role: .destructive) { model.data.courses.removeAll { $0.id == course.id } }
                    }
                } header: { Text(course.name) }
            }
            Button("Add course") { model.data.courses.append(.standard(String(localized: "New course"))) }
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
            Text("⌥-click a cube in the menu bar panel to say where the class is now. The class keeps advancing from there.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func move(_ id: UUID, _ by: Int) {
        guard let i = model.data.courses.firstIndex(where: { $0.id == id }), model.data.courses.indices.contains(i + by) else { return }
        model.data.courses.swapAt(i, i + by)
    }
}

struct ExamsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                ForEach($m.data.manual) { $x in
                    HStack {
                        TextField("Title", text: $x.title)
                        Picker("", selection: $x.courseID) {
                            Text("No course").tag(UUID?.none)
                            ForEach(model.data.courses) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden().frame(width: 170)
                        DatePicker("", selection: $x.due).labelsHidden()
                        Button { model.data.manual.removeAll { $0.id == x.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Add exam or deadline") {
                    model.data.manual.append(ManualDeadline(title: String(localized: "Exam"), due: Calendar.current.startOfDay(for: .now).addingTimeInterval(14 * 86400 + 9 * 3600), courseID: model.data.courses.first?.id))
                }
            } footer: {
                Text("For exams and deadlines that aren't on Moodle. They show up in the menu bar, reminders and the calendar like Moodle deadlines.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.data.manual) { model.push() }
    }
}
