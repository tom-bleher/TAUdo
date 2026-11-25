import Foundation

/// A lecture or recitation recording on Panopto, as listed by the course's Panopto block on Moodle.
struct Recording: Codable, Hashable, Sendable {
    var name: String
    var url: URL
}

enum Recordings {
    /// Only Panopto viewer links over https are kept: the list comes from a web page.
    static func valid(_ r: Recording) -> Bool {
        r.url.scheme == "https" && (r.url.host?.hasSuffix(".panopto.eu") == true || r.url.host?.hasSuffix(".panopto.com") == true)
    }

    private static let recitation = try! NSRegularExpression(pattern: #"תרגול|recitation|tutorial"#, options: .caseInsensitive)
    /// The number after a word for a class session ("הרצאה 5", "תרגול 07", "Lecture 12").
    private static let keyed = try! NSRegularExpression(
        pattern: #"(?:הרצאה|שיעור|תרגול|lecture|lesson|class|recitation|tutorial)\s*(?:מס['׳"]?\s*|#\s*)?(\d{1,2})(?!\d)"#, options: .caseInsensitive)
    /// A number leading the name ("07 - Course - …").
    private static let leading = try! NSRegularExpression(pattern: #"^\s*(\d{1,2})(?!\d)"#)

    static func kind(_ name: String) -> TrackKind {
        matches(recitation, name) == nil ? .lecture : .recitation
    }

    /// The session number in a recording's name, or nil (dates and course numbers don't count).
    static func number(_ name: String) -> Int? {
        for r in [keyed, leading] {
            if let m = matches(r, name), let g = Range(m.range(at: 1), in: name), let n = Int(name[g]), n > 0 { return n }
        }
        return nil
    }

    /// Recordings by row kind and session number. Unnumbered ones are only listed on the course.
    static func byCube(_ list: [Recording]) -> [TrackKind: [Int: [Recording]]] {
        var out: [TrackKind: [Int: [Recording]]] = [:]
        for r in list { if let n = number(r.name) { out[kind(r.name), default: [:]][n, default: []].append(r) } }
        return out
    }

    /// For the course's list: numbered first, in order, then the rest by name.
    static func sorted(_ list: [Recording]) -> [Recording] {
        list.sorted { a, b in
            switch (number(a.name), number(b.name)) {
            case let (x?, y?) where x != y || kind(a.name) != kind(b.name):
                return kind(a.name) != kind(b.name) ? kind(a.name) == .lecture : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    private static func matches(_ r: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }
}
