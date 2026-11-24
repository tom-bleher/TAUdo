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
        case .empty: Color.primary.opacity(0.07)
        }
    }
}

/// The menu bar panel: a "Due" tab and a "Courses" tab, one at a time.
struct PanelView: View {
    enum Tab: String { case due, courses }

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("panelTab") private var tab = Tab.due
    @State private var contentHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    notices
                    switch tab {
                    case .due: DeadlineList()
                    case .courses: CourseList()
                    }
                }
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // Menu bar windows size to their content; a bare ScrollView has none, so size it explicitly.
            .frame(height: min(max(contentHeight, 80), 600))
        }
        .frame(width: 460)
        .onAppear { model.panelDidOpen(); model.refreshIfStale() }
        .onDisappear { model.panelDidClose() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text("Due").tag(Tab.due)
                Text("Courses").tag(Tab.courses)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            Button { Task { await model.refresh() } } label: {
                if model.syncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless).disabled(model.syncing).help(Text("Refresh from Moodle"))
            .keyboardShortcut("r")
            Menu {
                Text(syncText)
                Divider()
                Button("Connect Moodle in browser…") { model.connect() }
                Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
                Button("Settings…") { show { openSettings() } }.keyboardShortcut(",")
                Divider()
                Button("Quit TAUdo") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var syncText: String {
        guard let t = model.data.lastSync else { return String(localized: "Not synced yet") }
        return String(localized: "Synced \(t.relative())")
    }

    /// Only things that need you: errors, connecting Moodle, linking courses.
    @ViewBuilder private var notices: some View {
        if let e = model.loadError { Notice(text: e, systemImage: "exclamationmark.octagon.fill", color: .red) }
        if let e = model.feedError { Notice(text: e, systemImage: "exclamationmark.triangle.fill", color: .orange) }
        if model.data.settings.exportURL.isEmpty { ConnectCard() }
        if model.now > model.data.settings.semesterEnd.addingTimeInterval(14 * 86400) {
            HStack {
                Notice(text: String(localized: "The semester in Settings has ended. Set the new semester's dates so the class markers stay right."),
                       systemImage: "calendar.badge.exclamationmark", color: .blue)
                Button("Settings…") { show { openSettings() } }.controlSize(.small)
            }
        }
        if !model.unlinkedMoodleCourses.isEmpty { LinkCourses() }
    }

    /// Menu bar apps are background apps: bring the app forward so new windows aren't hidden.
    private func show(_ action: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        action()
    }
}

struct Notice: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConnectCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Moodle").font(.subheadline.weight(.semibold))
            Text(model.connectStatus ?? String(localized: "Log in to Moodle in your browser and copy your calendar link. TAUdo picks it up from the clipboard."))
                .font(.caption).foregroundStyle(model.connectStatus == nil ? .secondary : Color.blue)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Moodle in browser") { model.connect() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Moodle courses with deadlines that aren't tied to a course yet; one click links them.
struct LinkCourses: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which course is this?").font(.subheadline.weight(.semibold))
            ForEach(model.unlinkedMoodleCourses, id: \.self) { key in
                HStack {
                    Text(model.data.courseLabel(key)).lineLimit(1)
                    Spacer()
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
        .padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The course code plus a couple of its deadlines, to tell similar courses apart.
    private func sample(_ key: String) -> String {
        let titles = model.deadlines.filter { $0.event.courseKey == key }.prefix(2).map(\.title)
        let code = key.components(separatedBy: " - ").first { $0.allSatisfy(\.isNumber) }
        return ([code] + titles).compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: Due tab

struct DeadlineList: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    var body: some View {
        let open = model.open
        let shown = showAll ? open : Array(open.prefix(8))
        VStack(alignment: .leading, spacing: 2) {
            if open.isEmpty {
                Group { if model.data.events.isEmpty && model.data.manual.isEmpty { Text("No deadlines yet.") } else { Text("Nothing coming up.") } }
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(shown) { DeadlineRow(d: $0) }
            HStack(spacing: 14) {
                if open.count > 8 {
                    Button { showAll.toggle() } label: { showAll ? Text("Show less") : Text("\(open.count - shown.count) more…") }
                }
                let missed = model.overdue.count
                if missed > 0 {
                    Button { model.data.settings.showOverdue.toggle() } label: {
                        model.data.settings.showOverdue ? Text("Hide overdue") : Text("Show \(missed) overdue")
                    }
                }
            }
            .buttonStyle(.link).font(.caption).padding(.top, 4)
        }
    }
}

struct DeadlineRow: View {
    @Environment(AppModel.self) private var model
    let d: Deadline

    var body: some View {
        let left = d.due.timeIntervalSince(model.now)
        HStack(spacing: 8) {
            Button { model.toggle(d) } label: {
                Image(systemName: d.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(d.isDone ? .green : .secondary)
            }
            .buttonStyle(.borderless).help(Text("Mark done"))
            Circle().fill(Palette.course(d.courseIndex)).frame(width: 6, height: 6)
            Text(d.title).lineLimit(1).layoutPriority(1)
            Text(model.courseName(d)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(AppModel.remaining(d.due, now: model.now))
                .monospacedDigit()
                .foregroundStyle(left < 0 ? .red : left < 2 * 86400 ? .orange : .secondary)
                .help(d.due.long())
        }
        .font(.callout)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Mark done")) { model.toggle(d) }
        .contextMenu {
            if let s = d.event.url, let u = URL(string: s) { Button("Open in Moodle") { NSWorkspace.shared.open(u) } }
            Button { model.hide(d) } label: { d.isManual ? Text("Delete") : Text("Hide (not mine)") }
        }
    }
}

// MARK: Courses tab

struct CourseList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.data.courses.isEmpty {
                Text("No courses yet. Connect Moodle and pick your courses, or add one in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            // Iterate by id so deleting a course never leaves a stale index behind.
            ForEach(model.data.courses) { c in
                if let ci = model.data.courses.firstIndex(where: { $0.id == c.id }) { CourseCard(ci: ci) }
            }
            Text("Click a cube to change it · ⌥-click: the class is here · right-click: more")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
