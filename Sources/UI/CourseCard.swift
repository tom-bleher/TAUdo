import SwiftUI

/// One course: name, completion, lead over the class, and a row of cubes per track.
struct CourseCard: View {
    @Environment(AppModel.self) private var model
    let ci: Int

    private let cube: CGFloat = 12, gap: CGFloat = 3
    /// Cubes per line: a semester of two sessions a week. Longer rows wrap.
    private let perLine = 26

    var body: some View {
        let course = model.data.courses[ci]
        let (done, total) = Pacing.completion(course)
        let recordings = model.data.recordings(for: course)
        let byCube = Recordings.byCube(recordings)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Palette.course(ci)).frame(width: 8, height: 8)
                Text(course.name).font(.callout.weight(.semibold)).lineLimit(1)
                if model.data.pace(course) == .selfStudy { Tag(text: Text("self-study")) }
                Spacer(minLength: 8)
                lead(course)
                Text(verbatim: "\(total == 0 ? 0 : 100 * done / total)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contextMenu {
                if !recordings.isEmpty {
                    Menu("Recordings in Panopto") {
                        ForEach(Recordings.sorted(recordings), id: \.url) { r in Button(r.name) { NSWorkspace.shared.open(r.url) } }
                    }
                }
                if let folder = model.data.folder(for: course) { Button("Open course folder") { NSWorkspace.shared.open(folder) } }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(course.tracks.indices, id: \.self) { ti in row(course, ti, recordings: byCube) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// How far ahead of (or behind) the class you are in the course's first row (usually lectures).
    @ViewBuilder private func lead(_ course: Course) -> some View {
        if let t = course.tracks.first {
            let classPos = Pacing.classPosition(t, links: links(course, t), settings: model.data.settings, now: model.now)
            let lead = Pacing.yourPosition(t) - classPos
            if lead != 0 {
                Tag(text: Text(verbatim: lead > 0 ? "+\(lead)" : "−\(-lead)").monospacedDigit(), color: lead > 0 ? Palette.cell(.done) : .orange)
                    .help(lead > 0 ? Text("\(lead) ahead of the class") : Text("\(-lead) behind the class"))
            }
        }
    }

    private func links(_ course: Course, _ t: Track) -> [Int: MoodleEvent] {
        t.kind == .homework ? model.data.homeworkLinks(course: ci) : [:]
    }

    private func row(_ course: Course, _ ti: Int, recordings: [TrackKind: [Int: [Recording]]]) -> some View {
        let t = course.tracks[ti]
        let links = links(course, t)
        let classPos = Pacing.classPosition(t, links: links, settings: model.data.settings, now: model.now)
        let lines = stride(from: 0, to: t.count, by: perLine).map { $0..<min($0 + perLine, t.count) }
        return HStack(alignment: .top, spacing: 6) {
            Text(t.shortName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 28, height: cube, alignment: .leading)
                .help(t.name)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(lines, id: \.lowerBound) { line in
                    HStack(spacing: gap) {
                        ForEach(line, id: \.self) { i in
                            cell(t, ti, i, classPos: classPos, link: links[i], recordings: recordings[t.kind]?[i + 1] ?? [])
                            // The class marker sits in the gap after the last session the class has held.
                            // It takes no space (negative padding cancels the extra gap), so columns stay aligned.
                            if i == classPos - 1 && classPos < t.count {
                                Color.clear.frame(width: 0, height: cube)
                                    .overlay(Capsule().fill(Color.accentColor).frame(width: 2, height: cube + 4))
                                    .padding(.horizontal, -gap / 2)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ t: Track, _ ti: Int, _ i: Int, classPos: Int, link: MoodleEvent?, recordings: [Recording]) -> some View {
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
        if !recordings.isEmpty { tip += "\n" + String(localized: "⌘-click: watch in Panopto") }
        else if let f = files.first { tip += "\n" + String(localized: "⌘-click: open \(f.lastPathComponent)") }
        return Cube(fill: Palette.cell(state), stroke: stroke, size: cube)
            .help(tip)
            .accessibilityElement()
            .accessibilityLabel(tip)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.cycle(ci, ti, i) }
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                if mods.contains(.command), let r = recordings.first { NSWorkspace.shared.open(r.url) }
                else if mods.contains(.command), let f = files.first { NSWorkspace.shared.open(f) }
                else if mods.contains(.option) { model.setClassPosition(ci, ti, to: i + 1) }
                else { model.cycle(ci, ti, i) }
            }
            .contextMenu {
                // Two recordings for one session (e.g. two parts): name them apart.
                ForEach(recordings, id: \.url) { r in
                    Button { NSWorkspace.shared.open(r.url) } label: {
                        recordings.count > 1 ? Text("Watch “\(r.name)” in Panopto") : Text("Watch in Panopto")
                    }
                }
                ForEach(files.prefix(4), id: \.self) { f in
                    Button(String(localized: "Open \((files.count > 1 ? f.deletingLastPathComponent().lastPathComponent + "/" : "") + f.lastPathComponent)")) { NSWorkspace.shared.open(f) }
                }
                if !files.isEmpty || !recordings.isEmpty { Divider() }
                ForEach(CellState.allCases, id: \.self) { s in
                    Button(s.label) { model.set(ci, ti, i, s) }
                }
                Divider()
                Button("The class is here") { model.setClassPosition(ci, ti, to: i + 1) }
                if let u = link?.url.flatMap(URL.init(string:)) { Button("Open in Moodle") { NSWorkspace.shared.open(u) } }
            }
    }
}

/// One cube. Lifts slightly under the pointer so it reads as clickable.
private struct Cube: View {
    let fill: Color
    let stroke: Color
    let size: CGFloat
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        shape.fill(fill)
            .overlay(shape.fill(Color.primary.opacity(hover ? 0.16 : 0)))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1.5))
            .frame(width: size, height: size)
            .scaleEffect(hover ? 1.25 : 1)
            .animation(.easeOut(duration: 0.1), value: hover)
            .animation(.easeOut(duration: 0.15), value: fill)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}
