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

/// The menu bar panel: a "Due" tab and a "Courses" tab, one at a time.
struct PanelView: View {
    enum Tab: String { case due, courses }

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("panelTab") private var tab = Tab.due
    @State private var contentHeight: CGFloat = 400
    static let width: CGFloat = 470

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
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // Menu bar windows size to their content; a bare ScrollView has none, so size it explicitly.
            .frame(height: min(max(contentHeight, 80), 600))
        }
        .frame(width: PanelView.width)
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
            .buttonStyle(.borderless).disabled(model.syncing).help(Text("Refresh from Moodle") + Text(verbatim: " · " + syncText))
            .keyboardShortcut("r")
            Menu {
                Text(syncText)
                Divider()
                Button("Connect Moodle in browser…") { model.connect() }
                Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
                Button("Check for Updates…") { show { Updates.shared.check() } }
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
            Notice(text: String(localized: "The semester in Settings has ended. Set the new semester's dates so the class markers stay right."),
                   systemImage: "calendar.badge.exclamationmark", color: .blue) {
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

// MARK: Due tab

struct DeadlineList: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    private let limit = 8

    var body: some View {
        let open = model.open
        let shown = showAll ? open : Array(open.prefix(limit))
        let groups = Dictionary(grouping: shown) { DueGroup.of($0.due, now: model.now) }
        let first = DueGroup.allCases.first { groups[$0] != nil }
        let missed = model.overdue.count
        VStack(alignment: .leading, spacing: 0) {
            if open.isEmpty && !model.data.settings.exportURL.isEmpty { empty }
            ForEach(DueGroup.allCases, id: \.self) { g in
                if let items = groups[g] {
                    Text(g.label).font(.caption.weight(.semibold)).foregroundStyle(g == .overdue ? Color.red : .secondary)
                        .padding(.horizontal, DeadlineRow.inset).padding(.top, g == first ? 2 : 12).padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(items) { DeadlineRow(d: $0, group: g) }
                }
            }
            if open.count > limit || missed > 0 {
                HStack(spacing: 14) {
                    if open.count > limit {
                        Button { showAll.toggle() } label: { showAll ? Text("Show less") : Text("\(open.count - shown.count) more…") }
                    }
                    if missed > 0 {
                        Button { model.data.settings.showOverdue.toggle() } label: {
                            model.data.settings.showOverdue ? Text("Hide overdue") : Text("Show \(missed) overdue")
                        }
                    }
                }
                .buttonStyle(.link).font(.caption)
                .padding(.horizontal, DeadlineRow.inset).padding(.top, 10)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Group { if model.data.events.isEmpty && model.data.manual.isEmpty { Text("No deadlines yet.") } else { Text("Nothing coming up.") } }
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

/// One deadline: a tick in the course's colour, the title over "course · when", and the time left.
struct DeadlineRow: View {
    static let inset: CGFloat = 6

    @Environment(AppModel.self) private var model
    let d: Deadline
    let group: DueGroup
    @State private var hover = false

    var body: some View {
        let left = d.due.timeIntervalSince(model.now)
        let urgency: Color? = left < 0 ? .red : left < 86400 ? .orange : nil
        let link = d.event.url.flatMap(URL.init(string:))
        HStack(spacing: 9) {
            Button { model.toggle(d) } label: {
                Image(systemName: d.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(Palette.course(d.courseIndex))
            }
            .buttonStyle(.borderless).help(Text("Mark done"))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(d.title).lineLimit(1)
                    if d.isExam { Tag(text: Text("Exam")) }
                }
                Text(verbatim: Lang.joined(model.courseName(d), d.due.dueLabel(group)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if hover, let link {
                Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(Text("Open in Moodle"))
            }
            Group {
                if let urgency { Tag(text: Text(AppModel.remaining(d.due, now: model.now)).monospacedDigit(), color: urgency) }
                else { Text(AppModel.remaining(d.due, now: model.now)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .help(d.due.long())
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

// MARK: Courses tab

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
