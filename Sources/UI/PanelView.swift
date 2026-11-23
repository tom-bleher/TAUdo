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
        case .empty: Color.primary.opacity(0.06)
        }
    }
}

struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let e = model.loadError { banner(e, systemImage: "exclamationmark.octagon.fill", color: .red) }
                    if model.data.settings.exportURL.isEmpty { connectCard }
                    if let e = model.feedError { banner(e, systemImage: "exclamationmark.triangle.fill", color: .orange) }
                    if !model.unlinkedMoodleCourses.isEmpty { LinkCourses() }
                    DeadlineList()
                    DayStrip()
                    // Iterate by id so deleting a course never leaves a stale index behind.
                    ForEach(model.data.courses) { c in
                        if let ci = model.data.courses.firstIndex(where: { $0.id == c.id }) { CourseCard(ci: ci) }
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // Menu bar windows size to their content; a bare ScrollView has none, so size it explicitly.
            .frame(height: min(max(contentHeight, 120), 640))
        }
        .frame(width: 500)
        .onAppear { model.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("TAUdo").font(.headline)
            Spacer()
            Text(syncText).font(.caption).foregroundStyle(.secondary)
            if model.syncing {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh from Moodle")
            }
            Menu {
                Button("Connect Moodle in browser…") { model.connect() }
                Button("Install sync bookmark…") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
                Button("Settings…") { show { openSettings() } }.keyboardShortcut(",")
                Divider()
                Button("Quit TAUdo") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var syncText: String {
        guard let t = model.data.lastSync else { return "Not synced" }
        return "Synced " + t.formatted(.relative(presentation: .named))
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Moodle").font(.subheadline.weight(.semibold))
            Text(model.connectStatus ?? "Log in to Moodle in your browser and copy your calendar link. TAUdo picks it up from the clipboard and keeps deadlines in sync.")
                .font(.caption).foregroundStyle(model.connectStatus == nil ? .secondary : Color.blue)
            HStack {
                Button("Open Moodle in browser") { model.connect() }
                Button("Get sync bookmark") { MoodleConnect.openBookmarkletPage(key: model.data.settings.syncKey) }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Menu bar apps are background apps: bring the app forward so new windows aren't hidden.
    private func show(_ action: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        action()
    }
}

// MARK: Linking Moodle courses

/// Moodle courses with deadlines that aren't tied to a course yet; one click links them.
struct LinkCourses: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Link Moodle courses").font(.subheadline.weight(.semibold))
            Text("Pick which course each Moodle course is, so its homework fills the right cubes.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.unlinkedMoodleCourses, id: \.self) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.data.courseLabel(key)).lineLimit(1)
                        Text(sample(key)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Menu("Link to…") {
                        ForEach(model.data.courses) { c in Button(c.name) { model.link(key, to: c.id) } }
                    }
                    .controlSize(.small).fixedSize()
                }
            }
        }
        .padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sample(_ key: String) -> String {
        let titles = model.deadlines.filter { $0.event.courseKey == key }.prefix(2).map(\.title)
        // The course code (e.g. 0321213001) plus a couple of its deadlines, to tell similar courses apart.
        let code = key.components(separatedBy: " - ").first { $0.allSatisfy(\.isNumber) }
        return ([code] + titles).compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: Deadlines

struct DeadlineList: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    var body: some View {
        let open = model.open
        let shown = showAll ? open : Array(open.prefix(6))
        VStack(alignment: .leading, spacing: 4) {
            Text("Due").font(.subheadline.weight(.semibold))
            if open.isEmpty {
                Text(model.data.events.isEmpty && model.data.manual.isEmpty ? "No deadlines yet." : "Nothing open. Everything is submitted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(shown) { DeadlineRow(d: $0) }
            if open.count > shown.count || showAll && open.count > 6 {
                Button(showAll ? "Show less" : "\(open.count - shown.count) more…") { showAll.toggle() }
                    .buttonStyle(.link).font(.caption)
            }
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
            .buttonStyle(.borderless).help("Mark done")
            RoundedRectangle(cornerRadius: 1.5).fill(Palette.course(d.courseIndex)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if d.isExam { Image(systemName: "pencil.and.list.clipboard").font(.caption) }
                    Text(d.title).lineLimit(1)
                }
                Text(model.courseName(d)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(AppModel.remaining(d.due, now: model.now))
                .font(.callout.monospacedDigit().weight(left < 2 * 86400 ? .semibold : .regular))
                .foregroundStyle(left < 0 ? .red : left < 2 * 86400 ? .orange : .secondary)
                .help(d.due.formatted(date: .complete, time: .shortened))
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let s = d.event.url, let u = URL(string: s) { Button("Open in Moodle") { NSWorkspace.shared.open(u) } }
            Button(d.isManual ? "Delete" : "Hide (not mine)") { model.hide(d) }
        }
    }
}

/// Two weeks at a glance: one dot per open deadline, coloured by course.
struct DayStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: model.now)
        let open = model.open
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { k in
                let day = cal.date(byAdding: .day, value: k, to: today)!
                let due = open.filter { cal.isDate($0.due, inSameDayAs: day) }
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day())).font(.caption.monospacedDigit().weight(k == 0 ? .bold : .regular))
                    HStack(spacing: 2) {
                        ForEach(due.prefix(3)) { Circle().fill(Palette.course($0.courseIndex)).frame(width: 5, height: 5) }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(k == 0 ? Color.accentColor.opacity(0.12) : cal.isDateInWeekend(day) ? Color.primary.opacity(0.03) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .help(due.isEmpty ? day.formatted(date: .complete, time: .omitted) : due.map { "\(model.courseName($0)): \($0.title)" }.joined(separator: "\n"))
            }
        }
    }
}
