import SwiftUI

enum Palette {
    static let courses: [Color] = [.blue, .purple, .pink, .teal, .orange, .indigo, .mint, .brown]
    static func course(_ i: Int?) -> Color { i.map { courses[$0 % courses.count] } ?? .gray }

    static func cell(_ s: CellState) -> Color {
        switch s {
        case .done: Color(red: 0.18, green: 0.62, blue: 0.36)
        case .todo: Color(red: 0.88, green: 0.61, blue: 0)
        case .revisit: Color(red: 0.23, green: 0.45, blue: 0.85)
        case .skipped: Color.gray.opacity(0.45)
        case .empty: Color.primary.opacity(0.09)
        }
    }
}

/// The menu bar panel: "Deadlines", "Progress" and "Exams" tabs, one at a time.
struct PanelView: View {
    enum Tab: String { case due, exams, courses }

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("panelTab") private var tab = Tab.due
    @State private var contentHeight: CGFloat = 400
    @State private var adding: Bool
    static let width: CGFloat = 470

    /// `adding`: start with the add-deadline card open (snapshots).
    init(adding: Bool = false) { _adding = State(initialValue: adding) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                PanelContent(tab: $tab, adding: $adding)
                    .padding(12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // Menu bar windows size to their content; a bare ScrollView has none, so size it explicitly.
            .frame(height: min(max(contentHeight, 80), 600))
            Divider()
            footer
        }
        .frame(width: PanelView.width)
        .onAppear { model.panelDidOpen(); model.refreshIfStale() }
        .onDisappear { model.panelDidClose(); adding = false }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TabPicker(tab: $tab)
            Spacer()
            TabActions(tab: $tab, adding: $adding)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Where things stand (last sync, anything hidden) and the app's menu.
    private var footer: some View {
        let hidden = model.hiddenCourseCount
        return HStack(spacing: 6) {
            Group {
                if model.syncing { Text("Syncing…") }
                else if let t = model.data.lastSync { Text("Synced \(t.relative())") }
                else { Text("Not synced yet") }
            }
            .foregroundStyle(.secondary)
            if hidden > 0 {
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Button { SettingsTab.moodle.open(openSettings) } label: { Text("\(hidden) hidden courses") }
                    .buttonStyle(.link).help(Text("Moodle courses you marked as not yours. Show them again in Settings."))
            }
            Spacer()
            Menu {
                Button("Open TAUdo Window") { show { openWindow(id: AppWindow.id) } }.keyboardShortcut("o")
                Button("Settings…") { show { openSettings() } }.keyboardShortcut(",")
                Button("Check for Updates…") { show { Updates.shared.check() } }
                Divider()
                Button("Connect Moodle in browser…") { model.connect() }
                Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey, base: model.data.settings.moodleBaseURL) }
                Divider()
                Button("Quit TAUdo") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    /// Menu bar apps are background apps: bring the app forward so new windows aren't hidden.
    private func show(_ action: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        action()
    }
}

/// The Deadlines / Progress / Exams switch, in the panel and the window.
struct TabPicker: View {
    @Binding var tab: PanelView.Tab

    var body: some View {
        Picker("", selection: $tab) {
            Text("Deadlines").tag(PanelView.Tab.due)
            Text("Progress").tag(PanelView.Tab.courses)
            Text("Exams").tag(PanelView.Tab.exams)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}

/// Add an exam or deadline, and refresh: next to the tabs in the panel, in the window's toolbar.
struct TabActions: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: PanelView.Tab
    @Binding var adding: Bool

    var body: some View {
        Button { if tab == .courses { tab = .due }; adding.toggle() } label: { Image(systemName: "plus") }
            .help(Text("Add exam or deadline")).keyboardShortcut("n")
        Button { Task { await model.refresh() } } label: {
            if model.syncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
        }
        .disabled(model.syncing).help(Text("Refresh from Moodle")).keyboardShortcut("r")
    }
}

/// What's under the tabs, in the panel and the window: notices, the add card, and the tab's list.
struct PanelContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Binding var tab: PanelView.Tab
    @Binding var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            notices
            // Show the tab the new item lands on, so it doesn't seem to vanish.
            if adding { AddDeadline { isExam in adding = false; if let isExam { tab = isExam ? .exams : .due } } }
            switch tab {
            case .due: DeadlineList()
            case .exams: ExamList()
            case .courses: CourseList()
            }
        }
    }

    /// Only things that need you: errors, connecting Moodle, linking courses.
    @ViewBuilder private var notices: some View {
        if let e = model.loadError { Notice(text: e, systemImage: "exclamationmark.octagon.fill", color: .red) }
        if let e = model.feedError { Notice(text: e, systemImage: "exclamationmark.triangle.fill", color: .orange) }
        if model.data.settings.exportURL.isEmpty { ConnectCard() }
        if model.now > model.data.settings.semesterEnd.addingTimeInterval(14 * 86400) {
            Notice(text: String(localized: "The semester in Settings has ended. Set the new semester's dates so the class markers stay right."),
                   systemImage: "calendar.badge.exclamationmark", color: .blue) {
                Button("Settings…") { SettingsTab.general.open(openSettings) }.controlSize(.small)
            }
        }
        if !model.unlinkedMoodleCourses.isEmpty { LinkCourses() }
    }
}

/// A tinted card for things that need attention, with an optional action on the trailing side.
struct Notice<Action: View>: View {
    let text: String
    let systemImage: String
    let color: Color
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action
        }
        .font(.caption)
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension Notice where Action == EmptyView {
    init(text: String, systemImage: String, color: Color) {
        self.init(text: text, systemImage: systemImage, color: color) { EmptyView() }
    }
}

/// A small rounded label, e.g. "Exam" or "self-study".
struct Tag: View {
    let text: Text
    var color: Color = .secondary

    var body: some View {
        text.font(.caption2.weight(.medium)).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct ConnectCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
            Text("Connect Moodle").font(.headline)
            Text(model.connectStatus ?? String(localized: "Log in to Moodle in your browser and copy your calendar link. TAUdo picks it up from the clipboard."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Moodle in browser") { model.connect() }.buttonStyle(.borderedProminent).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 24)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Moodle courses with deadlines that aren't tied to a course yet; one click links them.
struct LinkCourses: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.unlinkedMoodleCourses, id: \.self) { key in
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.data.courseLabel(key)).font(.callout.weight(.medium)).lineLimit(1)
                        Text("Which course is this?").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Menu("Link to…") {
                        ForEach(model.data.courses) { c in Button(c.name) { model.link(key, to: c.id) } }
                        if !model.data.courses.isEmpty { Divider() }
                        Button("Add as a new course") { model.addCourse(fromMoodle: key) }
                        Button("Not my course") { model.ignore(moodleCourse: key) }
                    }
                    .controlSize(.small).fixedSize()
                }
                .help(sample(key))
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The course code plus a couple of its deadlines, to tell similar courses apart.
    private func sample(_ key: String) -> String {
        let titles = model.deadlines.filter { $0.event.courseKey == key }.prefix(2).map(\.title)
        let code = key.components(separatedBy: " - ").first { $0.allSatisfy(\.isNumber) }
        return ([code] + titles).compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: Deadlines tab

struct DeadlineList: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    @AppStorage("panelShowsDone") private var showDone = false

    var body: some View {
        let limit = model.data.settings.listLimit
        let open = model.open
        let done = model.completed
        let shown = showAll ? open : Array(open.prefix(limit))
        let missed = model.overdue.count
        VStack(alignment: .leading, spacing: 0) {
            if open.isEmpty && !(showDone && !done.isEmpty) && !model.data.settings.exportURL.isEmpty { empty }
            DueSections(items: shown)
            if showDone && !done.isEmpty {
                Text("Done").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, DeadlineRow.inset).padding(.top, open.isEmpty ? 2 : 12).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(done) { DeadlineRow(d: $0, group: .later) }
            }
            if open.count > limit || missed > 0 || !done.isEmpty {
                HStack(spacing: 14) {
                    if open.count > limit {
                        Button { showAll.toggle() } label: { showAll ? Text("Show less") : Text("\(open.count - shown.count) more…") }
                    }
                    if missed > 0 {
                        Button { model.data.settings.showOverdue.toggle() } label: {
                            model.data.settings.showOverdue ? Text("Hide overdue") : Text("Show \(missed) overdue")
                        }
                    }
                    if !done.isEmpty {
                        Button { showDone.toggle() } label: { showDone ? Text("Hide done") : Text("Show \(done.count) done") }
                    }
                }
                .buttonStyle(.link).font(.caption)
                .padding(.horizontal, DeadlineRow.inset).padding(.top, 10)
            }
        }
    }

    private var empty: some View {
        EmptyNote(systemImage: "checkmark.circle") {
            if model.data.events.isEmpty && model.data.manual.isEmpty { Text("No deadlines yet.") } else { Text("Nothing coming up.") }
        }
    }
}

/// Deadlines under day headings (Today, Tomorrow, …).
struct DueSections: View {
    @Environment(AppModel.self) private var model
    let items: [Deadline]
    var examTags = true

    var body: some View {
        let groups = Dictionary(grouping: items) { DueGroup.of($0.due, now: model.now) }
        let first = DueGroup.allCases.first { groups[$0] != nil }
        ForEach(DueGroup.allCases, id: \.self) { g in
            if let items = groups[g] {
                Text(g.label).font(.caption.weight(.semibold)).foregroundStyle(g == .overdue ? Color.red : .secondary)
                    .padding(.horizontal, DeadlineRow.inset).padding(.top, g == first ? 2 : 12).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { DeadlineRow(d: $0, group: g, examTag: examTags) }
            }
        }
    }
}

/// A large faint icon over a line of text, for an empty tab.
struct EmptyNote<Label: View>: View {
    let systemImage: String
    @ViewBuilder var label: Label

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            label.font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 24)
    }
}

// MARK: Exams tab

struct ExamList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let exams = model.exams
        VStack(alignment: .leading, spacing: 0) {
            if exams.isEmpty {
                EmptyNote(systemImage: "graduationcap") {
                    if model.data.settings.fetchExams { Text("No upcoming exams.") }
                    else {
                        VStack(spacing: 8) {
                            Text("Exam dates from Arazim are off.")
                            Button("Settings…") { SettingsTab.exams.open(openSettings) }.controlSize(.small)
                        }
                    }
                }
            }
            DueSections(items: exams, examTags: false)
        }
    }
}

/// One deadline: a tick in the course's colour, the title over "course · when", and the time left.
struct DeadlineRow: View {
    static let inset: CGFloat = 6

    @Environment(AppModel.self) private var model
    let d: Deadline
    let group: DueGroup
    var examTag = true
    @State private var hover = false

    var body: some View {
        let left = d.due.timeIntervalSince(model.now)
        let urgency: Color? = left < 0 ? .red : left < 86400 ? .orange : nil
        let link = model.data.moodleURL(for: d.event)
        HStack(spacing: 9) {
            Button { model.toggle(d) } label: {
                Image(systemName: d.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(Palette.course(d.courseIndex))
            }
            .buttonStyle(.borderless).help(d.isDone ? Text("Mark not done") : Text("Mark done"))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(d.title).lineLimit(1).strikethrough(d.isDone).foregroundStyle(d.isDone ? .secondary : .primary)
                    if examTag && d.isExam { Tag(text: Text("Exam")) }
                }
                Text(verbatim: Lang.joined(model.courseName(d), d.due.dueLabel(group, time: !d.event.isAllDay)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if hover, let link {
                Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(Text("Open in Moodle"))
            }
            if !d.isDone {
                Group {
                    if let urgency { Tag(text: Text(AppModel.remaining(d.due, now: model.now)).monospacedDigit(), color: urgency) }
                    else { Text(AppModel.remaining(d.due, now: model.now)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .help(d.due.long(time: !d.event.isAllDay))
            }
        }
        .font(.callout)
        .padding(.vertical, 5).padding(.horizontal, Self.inset)
        .background(Color.primary.opacity(hover ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Mark done")) { model.toggle(d) }
        .contextMenu {
            if let link { Button("Open in Moodle") { NSWorkspace.shared.open(link) } }
            Button { model.hide(d) } label: { d.isManual ? Text("Delete") : Text("Hide (not mine)") }
        }
    }
}

// MARK: Progress tab

struct CourseList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.data.courses.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text("No courses yet. Connect Moodle and pick your courses, or add one in Settings.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 24)
            } else {
                // Iterate by id so deleting a course never leaves a stale index behind.
                ForEach(model.data.courses) { c in
                    if let ci = model.data.courses.firstIndex(where: { $0.id == c.id }) { CourseCard(ci: ci) }
                }
                CubeLegend()
            }
        }
    }
}

/// What the cube colours mean, with the click shortcuts behind the question mark.
struct CubeLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([CellState.done, .todo, .revisit, .skipped], id: \.self) { s in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Palette.cell(s)).frame(width: 9, height: 9)
                    Text(s.label)
                }
            }
            HStack(spacing: 4) {
                Capsule().fill(Color.accentColor).frame(width: 2, height: 11)
                Text("The class is here")
            }
            Spacer(minLength: 0)
            Image(systemName: "questionmark.circle")
                .help(Text("Click a cube to change it · ⌥-click: the class is here · right-click: more"))
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.top, 2)
    }
}

/// A card for adding an exam or deadline of your own without leaving the panel.
struct AddDeadline: View {
    @Environment(AppModel.self) private var model
    /// Called with whether the added item is an exam, or nil when cancelled.
    var onClose: (_ addedExam: Bool?) -> Void
    @State private var title = ""
    @State private var due = ManualDeadline.suggestedDue()
    @State private var courseID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Exam or deadline")).labelsHidden().textFieldStyle(.roundedBorder)
                .focused($focused).onSubmit(add)
            HStack(spacing: 8) {
                Picker("Courses", selection: $courseID) {
                    Text("No course").tag(UUID?.none)
                    ForEach(model.data.courses) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden().frame(maxWidth: 190)
                DatePicker("Due", selection: $due).labelsHidden().fixedSize()
                Spacer(minLength: 0)
                Button("Cancel") { onClose(nil) }.keyboardShortcut(.cancelAction)
                Button("Add", action: add).buttonStyle(.borderedProminent).disabled(trimmed.isEmpty)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { focused = true }
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }

    private func add() {
        guard !trimmed.isEmpty else { return }
        model.addDeadline(title: trimmed, due: due, courseID: courseID)
        onClose(Classifier.isExam(trimmed))
    }
}
