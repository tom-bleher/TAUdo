import Foundation

/// One VEVENT from a Moodle iCal export.
struct MoodleEvent: Codable, Hashable, Identifiable, Sendable {
    var uid: String
    var summary: String
    var description: String = ""
    var location: String?
    var categories: [String] = []
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var url: String?

    var id: String { uid }
    /// Moodle puts the course shortname in CATEGORIES.
    var courseKey: String? { categories.first }
    /// Moodle UIDs look like "12345@moodle.tau.ac.il".
    var moodleEventID: Int? { uid.split(separator: "@").first.flatMap { Int($0) } }
    /// Deadlines are exported as zero-length events at the due time.
    var due: Date { end }
}

/// Minimal RFC 5545 reader — enough for Moodle's export (folded lines, TEXT escapes, UTC/TZID/date values).
enum ICS {
    static let defaultTimeZone = TimeZone(identifier: "Asia/Jerusalem")!

    static func unfold(_ raw: String) -> [String] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !out.isEmpty {
                out[out.count - 1] += line.dropFirst()
            } else {
                out.append(line)
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n", "N": out.append("\n")
            case ",", ";", "\\": out.append(n)
            default: out.append(c); out.append(n)
            }
        }
        return out
    }

    /// Returns (date, isAllDay). Floating times are read in `defaultTimeZone`.
    static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter(\.isNumber)
        if v.count == 8 || params["VALUE"]?.uppercased() == "DATE" {
            guard digits.count >= 8 else { return nil }
            let d = Array(digits)
            var c = DateComponents()
            c.year = Int(String(d[0..<4])); c.month = Int(String(d[4..<6])); c.day = Int(String(d[6..<8]))
            var cal = Calendar(identifier: .gregorian); cal.timeZone = defaultTimeZone
            return cal.date(from: c).map { ($0, true) }
        }
        guard digits.count == 14 else { return nil }
        let d = Array(digits)
        var c = DateComponents()
        c.year = Int(String(d[0..<4])); c.month = Int(String(d[4..<6])); c.day = Int(String(d[6..<8]))
        c.hour = Int(String(d[8..<10])); c.minute = Int(String(d[10..<12])); c.second = Int(String(d[12..<14]))
        var cal = Calendar(identifier: .gregorian)
        if v.hasSuffix("Z") { cal.timeZone = TimeZone(identifier: "UTC")! }
        else { cal.timeZone = params["TZID"].flatMap(TimeZone.init(identifier:)) ?? defaultTimeZone }
        return cal.date(from: c).map { ($0, false) }
    }

    private static func property(_ line: String) -> (name: String, params: [String: String], value: String)? {
        var inQuotes = false
        guard let colon = line.firstIndex(where: { ch in
            if ch == "\"" { inQuotes.toggle() }
            return ch == ":" && !inQuotes
        }) else { return nil }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
        var params: [String: String] = [:]
        for seg in head.dropFirst() {
            let kv = seg.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return (String(head.first ?? "").uppercased(), params, String(line[line.index(after: colon)...]))
    }

    static func parse(_ raw: String) -> [MoodleEvent] {
        var events: [MoodleEvent] = []
        var cur: [String: (params: [String: String], value: String)] = [:]
        var cats: [String] = []
        var inEvent = false, inAlarm = false
        for line in unfold(raw) {
            let line = line.trimmingCharacters(in: .whitespaces)
            switch line {
            case "BEGIN:VEVENT": inEvent = true; cur = [:]; cats = []; continue
            case "BEGIN:VALARM": inAlarm = true; continue
            case "END:VALARM": inAlarm = false; continue
            case "END:VEVENT":
                inEvent = false
                guard let uid = cur["UID"]?.value.trimmingCharacters(in: .whitespaces), !uid.isEmpty,
                      let s = cur["DTSTART"], let (start, allDay) = parseDate(s.value, params: s.params) else { continue }
                let end = cur["DTEND"].flatMap { parseDate($0.value, params: $0.params)?.0 } ?? start
                let text = { (k: String) in cur[k].map { unescape($0.value).trimmingCharacters(in: .whitespacesAndNewlines) } }
                let desc = text("DESCRIPTION") ?? ""
                events.append(MoodleEvent(
                    uid: uid, summary: text("SUMMARY") ?? "(untitled)", description: desc,
                    location: text("LOCATION").flatMap { $0.isEmpty ? nil : $0 },
                    categories: cats, start: start, end: end, isAllDay: allDay,
                    url: text("URL").flatMap { $0.isEmpty ? nil : $0 } ?? firstURL(in: desc)))
                continue
            default: break
            }
            guard inEvent, !inAlarm, let p = property(line) else { continue }
            if p.name == "CATEGORIES" {
                cats += splitUnescapedCommas(p.value).map { unescape($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                cur[p.name] = (p.params, p.value)
            }
        }
        return events
    }

    private static func splitUnescapedCommas(_ s: String) -> [String] {
        var parts: [String] = [], cur = "", escaped = false
        for c in s {
            if c == "," && !escaped { parts.append(cur); cur = ""; continue }
            escaped = (c == "\\" && !escaped)
            cur.append(c)
        }
        parts.append(cur)
        return parts
    }

    private static func firstURL(in text: String) -> String? {
        guard let r = text.range(of: #"https?://[^\s<>"]+/mod/[^\s<>"]+"#, options: .regularExpression) else { return nil }
        return String(text[r])
    }
}
