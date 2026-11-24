import Foundation

enum MoodleFeed {
    struct FeedError: LocalizedError { var errorDescription: String? }

    /// Accepts webcal:// or https:// Moodle export links; fills in "all events, custom range" if missing.
    static func normalize(_ raw: String) throws -> URL {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^webcal://", with: "https://", options: [.regularExpression, .caseInsensitive])
        guard var c = URLComponents(string: s), c.scheme == "https", c.host != nil,
              c.path.hasSuffix("/calendar/export_execute.php") else {
            throw FeedError(errorDescription: String(localized: "Not a Moodle calendar export link (…/calendar/export_execute.php)."))
        }
        var items = c.queryItems ?? []
        guard items.contains(where: { $0.name == "authtoken" }) else { throw FeedError(errorDescription: String(localized: "The export link is incomplete (no authtoken).")) }
        if !items.contains(where: { $0.name == "preset_what" }) { items.append(.init(name: "preset_what", value: "all")) }
        if !items.contains(where: { $0.name == "preset_time" }) { items.append(.init(name: "preset_time", value: "custom")) }
        c.queryItems = items
        return c.url!
    }

    static func fetch(_ exportURL: String) async throws -> [MoodleEvent] {
        var req = URLRequest(url: try normalize(exportURL), timeoutInterval: 20)
        req.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw FeedError(errorDescription: String(localized: "Moodle returned HTTP \(h.statusCode). The academic year may have changed: reconnect Moodle."))
        }
        let text = String(decoding: data, as: UTF8.self)
        if text.range(of: "invalid authentication", options: .caseInsensitive) != nil {
            throw FeedError(errorDescription: String(localized: "Moodle rejected the calendar link. Reconnect Moodle to get a new one."))
        }
        guard text.contains("BEGIN:VCALENDAR") else {
            throw FeedError(errorDescription: String(localized: "Moodle returned a web page instead of a calendar. Reconnect Moodle."))
        }
        return ICS.parse(text)
    }
}
