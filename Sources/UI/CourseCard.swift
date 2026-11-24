import SwiftUI

/// One course: name, completion, lead over the class, and a row of cubes per track.
struct CourseCard: View {
    @Environment(AppModel.self) private var model
    let ci: Int

    private let cube: CGFloat = 12, gap: CGFloat = 3

    var body: some View {
        let course = model.data.courses[ci]
        let (done, total) = Pacing.completion(course)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Palette.course(ci)).frame(width: 7, height: 7)
                Text(course.name).font(.callout.weight(.semibold)).lineLimit(1)
                if course.pace == .selfStudy { Text("self-study").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                lead(course)
                Text(verbatim: "\(total == 0 ? 0 : 100 * done / total)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contextMenu {
                if let folder = model.data.folder(for: course) { Button("Open course folder") { NSWorkspace.shared.open(folder) } }
            }
            ForEach(course.tracks.indices, id: \.self) { ti in row(course, ti) }
        }
    }

    /// How far ahead of (or behind) the class you are in the course's first row (usually lectures).
    @ViewBuilder private func lead(_ course: Course) -> some View {
        if let t = course.tracks.first {
            let classPos = Pacing.classPosition(t, links: links(course, t), settings: model.data.settings, now: model.now)
            let lead = Pacing.yourPosition(t) - classPos
            if lead != 0 {
                Text(verbatim: lead > 0 ? "+\(lead)" : "−\(-lead)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(lead > 0 ? Palette.cell(.done) : .orange)
                    .help(lead > 0 ? Text("\(lead) ahead of the class") : Text("\(-lead) behind the class"))
            }
        }
    }

    private func links(_ course: Course, _ t: Track) -> [Int: MoodleEvent] {
        t.kind == .homework ? model.data.homeworkLinks(course: ci) : [:]
    }

    private func row(_ course: Course, _ ti: Int) -> some View {
        let t = course.tracks[ti]
        let links = links(course, t)
        let classPos = Pacing.classPosition(t, links: links, settings: model.data.settings, now: model.now)
        return HStack(spacing: 8) {
            Text(t.shortName).font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                .help(t.name)
            HStack(spacing: gap) {
                ForEach(t.cells.indices, id: \.self) { i in
                    cell(t, ti, i, classPos: classPos, link: links[i])
                    // The class marker sits in the gap after the last session the class has held.
                    // It takes no space (negative padding cancels the extra gap), so columns stay aligned.
                    if i == classPos - 1 && classPos < t.count {
                        Color.clear.frame(width: 0, height: cube)
                            .overlay(Capsule().fill(Color.accentColor).frame(width: 2, height: cube + 4))
                            .padding(.horizontal, -gap / 2)
                            .help(Text("The class is here"))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func cell(_ t: Track, _ ti: Int, _ i: Int, classPos: Int, link: MoodleEvent?) -> some View {
        let state = t.cells[i]
        let files = model.files[model.data.courses[ci].id]?.urls(t.kind, i + 1) ?? []
        let open = state == .empty || state == .todo
        let now = model.now
        let overdue = open && (link.map { $0.due < now } ?? false)
        let dueSoon = open && (link.map { $0.due >= now && $0.due < now.addingTimeInterval(3 * 86400) } ?? false)
        let stroke: Color = overdue ? .red : dueSoon ? .orange : .clear
        var tip = "\(t.name) \(i + 1): \(state.label)"
        if let link { tip += "\n" + String(localized: "Due \(link.due.medium())") }
        if i < classPos { tip += "\n" + String(localized: "The class has covered this") }
        if let f = files.first { tip += "\n" + String(localized: "⌘-click: open \(f.lastPathComponent)") }
        return RoundedRectangle(cornerRadius: 3)
            .fill(Palette.cell(state))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(stroke, lineWidth: 1.5))
            .frame(width: cube, height: cube)
            .contentShape(Rectangle())
            .help(tip)
            .accessibilityElement()
            .accessibilityLabel(tip)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.cycle(ci, ti, i) }
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                if mods.contains(.command), let f = files.first { NSWorkspace.shared.open(f) }
                else if mods.contains(.option) { model.setClassPosition(ci, ti, to: i + 1) }
                else { model.cycle(ci, ti, i) }
            }
            .contextMenu {
                ForEach(files.prefix(4), id: \.self) { f in
                    Button(String(localized: "Open \((files.count > 1 ? f.deletingLastPathComponent().lastPathComponent + "/" : "") + f.lastPathComponent)")) { NSWorkspace.shared.open(f) }
                }
                if !files.isEmpty { Divider() }
                ForEach(CellState.allCases, id: \.self) { s in
                    Button(s.label) { model.set(ci, ti, i, s) }
                }
                Divider()
                Button("The class is here") { model.setClassPosition(ci, ti, to: i + 1) }
                if let u = link?.url.flatMap(URL.init(string:)) { Button("Open in Moodle") { NSWorkspace.shared.open(u) } }
            }
    }
}
