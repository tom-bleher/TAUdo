import SwiftUI

struct CourseCard: View {
    @Environment(AppModel.self) private var model
    let ci: Int

    private let cube: CGFloat = 12.5, gap: CGFloat = 2.5

    var body: some View {
        let course = model.data.courses[ci]
        let (done, total) = Pacing.completion(course)
        let links = model.data.homeworkLinks(course: ci)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Palette.course(ci)).frame(width: 8, height: 8)
                Text(course.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if course.pace == .selfStudy {
                    Text("self-study").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                if let folder = model.data.folder(for: course) {
                    Button { NSWorkspace.shared.open(folder) } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary).help("Open \(folder.path)")
                }
                Spacer()
                Text("\(done)/\(total) · \(total == 0 ? 0 : 100 * done / total)%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1))).progressViewStyle(.linear).tint(Palette.cell(.done)).controlSize(.small)
            ForEach(course.tracks.indices, id: \.self) { ti in
                row(course, ti, links: course.tracks[ti].kind == .homework ? links : [:])
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func row(_ course: Course, _ ti: Int, links: [Int: MoodleEvent]) -> some View {
        let t = course.tracks[ti]
        let s = model.data.settings
        let classPos = Pacing.classPosition(t, links: links, settings: s, now: model.now)
        let planned = Pacing.plannedPosition(t, course: course, classPos: classPos, settings: s, now: model.now)
        let lead = Pacing.yourPosition(t) - classPos
        return HStack(spacing: 6) {
            Text(t.shortName).font(.caption2).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                .help(t.name)
            HStack(spacing: gap) {
                ForEach(t.cells.indices, id: \.self) { i in
                    cell(t, ti, i, planned: planned, classPos: classPos, link: links[i])
                }
            }
            .overlay(alignment: .leading) {
                // The class marker: a bar just after the last session the class has held.
                if classPos > 0 && classPos < t.count {
                    Capsule().fill(Color.accentColor).frame(width: 2, height: cube + 5)
                        .offset(x: CGFloat(classPos) * (cube + gap) - gap / 2 - 1)
                        .help("Class is at \(t.name.lowercased()) \(classPos)")
                        .allowsHitTesting(false)
                }
            }
            Spacer(minLength: 0)
            Text(lead == 0 ? "=" : lead > 0 ? "+\(lead)" : "\(lead)")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(lead > 0 ? Palette.cell(.done) : lead < 0 ? .orange : .secondary)
                .frame(width: 26, alignment: .trailing)
                .help(lead == 0 ? "Level with the class" : lead > 0 ? "\(lead) ahead of the class" : "\(-lead) behind the class")
        }
    }

    private func cell(_ t: Track, _ ti: Int, _ i: Int, planned: Int, classPos: Int, link: MoodleEvent?) -> some View {
        let state = t.cells[i]
        let files = model.files[model.data.courses[ci].id]?.urls(t.kind, i + 1) ?? []
        let open = state == .empty || state == .todo
        let now = model.now
        let overdue = open && (link.map { $0.due < now } ?? false)
        let dueSoon = open && (link.map { $0.due >= now && $0.due < now.addingTimeInterval(3 * 86400) } ?? false)
        let behind = open && i < planned
        let stroke: Color = overdue ? .red : dueSoon ? .orange : behind ? .orange.opacity(0.7) : .primary.opacity(0.12)
        var tip = "\(t.name) \(i + 1): \(state.label)"
        if let link { tip += "\nDue " + link.due.formatted(date: .abbreviated, time: .shortened) }
        if i < classPos { tip += "\nClass has covered this" }
        if let f = files.first { tip += "\n⌘-click: open \(f.lastPathComponent)" }
        tip += "\nClick: next state · ⌥-click: class is here · right-click: more"
        return RoundedRectangle(cornerRadius: 3)
            .fill(Palette.cell(state))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(stroke, lineWidth: overdue || dueSoon || behind ? 1.5 : 1))
            .frame(width: cube, height: cube)
            .contentShape(Rectangle())
            .help(tip)
            .overlay(alignment: .bottomTrailing) {
                // A dot marks cubes with a file behind them (lecture video, pset folder, …).
                if !files.isEmpty { Circle().fill(state == .empty ? Color.secondary : .white.opacity(0.85)).frame(width: 3, height: 3).padding(1.5) }
            }
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                if mods.contains(.command), let f = files.first { NSWorkspace.shared.open(f) }
                else if mods.contains(.option) { model.setClassPosition(ci, ti, to: i + 1) }
                else { model.cycle(ci, ti, i) }
            }
            .contextMenu {
                ForEach(files.prefix(4), id: \.self) { f in
                    Button("Open " + (files.count > 1 ? f.deletingLastPathComponent().lastPathComponent + "/" : "") + f.lastPathComponent) { NSWorkspace.shared.open(f) }
                }
                if !files.isEmpty { Divider() }
                ForEach(CellState.allCases, id: \.self) { s in
                    Button(s.label.capitalized) { model.set(ci, ti, i, s) }
                }
                Divider()
                Button("Class is here") { model.setClassPosition(ci, ti, to: i + 1) }
                if let u = link?.url.flatMap(URL.init(string:)) { Button("Open in Moodle") { NSWorkspace.shared.open(u) } }
            }
    }
}
