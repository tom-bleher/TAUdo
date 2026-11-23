import AppKit
import Foundation

/// Connecting to Moodle through the user's own browser. TAUdo never sees the browser session or password:
/// it gets the calendar export link from the clipboard, or from the "TAUdo sync" bookmarklet via taudo://sync.
enum MoodleConnect {
    /// What the bookmarklet sends from a signed-in Moodle page.
    struct Payload: Decodable {
        /// This install's secret (Settings.syncKey), baked into the bookmark.
        var key: String?
        var base: String
        var exportURL: String?
        /// Moodle event IDs of assignment deadlines in the queried window.
        var assignIDs: [Int]
        /// Those Moodle still lists as needing action (not submitted).
        var pendingIDs: [Int]
        /// Course shortname → full name, from Moodle's calendar.
        var courses: [String: String]?

        var submittedIDs: Set<Int> { Set(assignIDs).subtracting(pendingIDs) }
    }

    /// A usable export link for `host`, or nil (wrong site, not an export link, or the guest account).
    static func exportLink(_ s: String, host: String) -> String? {
        guard let url = try? MoodleFeed.normalize(s), url.host == host,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.queryItems?.first(where: { $0.name == "userid" })?.value != "1" else { return nil }
        return url.absoluteString
    }

    static func payload(from url: URL) -> Payload? {
        guard url.scheme == "taudo", url.host == "sync",
              let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        guard d.utf8.count < 200_000, var p = try? JSONDecoder().decode(Payload.self, from: Data(d.utf8)) else { return nil }
        p.assignIDs = Array(p.assignIDs.prefix(2000)); p.pendingIDs = Array(p.pendingIDs.prefix(2000))
        return p
    }

    /// Waits for an export link to be copied (Moodle › Calendar › Export › Get calendar URL › copy).
    /// Only looks at the clipboard when it changes, and only until `deadline`.
    static func watchClipboard(host: String, until deadline: Date) async -> String? {
        let pb = NSPasteboard.general
        var seen = pb.changeCount
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard pb.changeCount != seen else { continue }
            seen = pb.changeCount
            if let s = pb.string(forType: .string), s.contains("export_execute.php"), let link = exportLink(s, host: host) { return link }
        }
        return nil
    }

    /// The bookmarklet: runs in a signed-in Moodle tab, submits Moodle's own export form for the link,
    /// asks Moodle's AJAX API which assignment deadlines are still to do, and hands both to TAUdo.
    static let bookmarkletSource = #"""
    (async () => {
      const M = window.M;
      if (!M || !M.cfg || !M.cfg.sesskey || !document.querySelector('a[href*="/login/logout.php"]')) {
        alert("TAUdo: open Moodle and log in first, then click this bookmark again."); return;
      }
      const base = M.cfg.wwwroot.replace(/\/+$/, ""), sesskey = M.cfg.sesskey;
      const from = Math.floor(Date.now() / 1000) - 150 * 86400;
      let exportURL = null;
      try {
        const doc = new DOMParser().parseFromString(await (await fetch(base + "/calendar/export.php", {credentials: "include"})).text(), "text/html");
        const form = doc.querySelector('form[action*="export.php"]') || doc.querySelector("form.mform");
        if (form) {
          const fd = new URLSearchParams();
          form.querySelectorAll('input[type="hidden"]').forEach(el => { if (el.name) fd.set(el.name, el.value); });
          fd.set("events[exportevents]", "all");
          fd.set("period[timeperiod]", form.querySelector('input[name="period[timeperiod]"][value="custom"]') ? "custom" : "recentupcoming");
          fd.set("generateurl", "1");
          const out = await (await fetch(base + "/calendar/export.php", {method: "POST", credentials: "include",
            headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: fd.toString()})).text();
          const m = out.match(/https?:\/\/[^"'<>\s]+calendar\/export_execute\.php\?[^"'<>\s]+/i);
          if (m) exportURL = m[0].replace(/&amp;/g, "&");
        }
      } catch (e) {}
      const ajax = async calls => (await fetch(base + "/lib/ajax/service.php?sesskey=" + encodeURIComponent(sesskey), {
        method: "POST", credentials: "include", headers: {"Content-Type": "application/json"},
        body: JSON.stringify(calls.map((c, i) => ({index: i, methodname: c[0], args: c[1]})))})).json();
      const assignIDs = [], pendingIDs = [], courses = {};
      try {
        const LIMIT = 50;
        const [pending] = await ajax([["core_calendar_get_action_events_by_timesort", {timesortfrom: from, limitnum: LIMIT}]]);
        if (!pending || pending.error || !pending.data) throw 0;   // no trustworthy to-do list: infer nothing
        const evs = pending.data.events || [];
        evs.forEach(e => pendingIDs.push(e.id));
        const until = evs.length >= LIMIT ? Math.max(...evs.map(e => e.timesort || e.timestart)) : Infinity;
        const months = [], d = new Date(from * 1000), end = new Date();
        d.setDate(1); end.setMonth(end.getMonth() + 4);
        while (d <= end && months.length < 14) { months.push([d.getFullYear(), d.getMonth() + 1]); d.setMonth(d.getMonth() + 1); }
        for (const v of await ajax(months.map(([y, m]) => ["core_calendar_get_calendar_monthly_view", {year: y, month: m, courseid: 1, day: 1}]))) {
          if (!v || v.error) continue;
          for (const w of v.data.weeks || []) for (const day of w.days || []) for (const e of day.events || []) {
            if (e.course && e.course.shortname) courses[e.course.shortname] = e.course.fullname || e.course.shortname;
            if (e.modulename === "assign" && e.eventtype === "due" && e.timestart >= from && e.timestart <= until) assignIDs.push(e.id);
          }
        }
      } catch (e) {}
      location.href = "taudo://sync?d=" + encodeURIComponent(JSON.stringify({key: "__KEY__", base, exportURL, assignIDs, pendingIDs, courses}));
    })();
    """#

    static func bookmarkletURL(key: String) -> String {
        let code = bookmarkletSource.replacingOccurrences(of: "__KEY__", with: key).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-_.!~*'()")
        return "javascript:" + code.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    /// Writes a small page with the draggable bookmark and opens it in the default browser.
    static func openBookmarkletPage(key: String) {
        let html = """
        <!doctype html><meta charset="utf-8"><title>TAUdo sync bookmark</title>
        <style>body{font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:560px;margin:4rem auto;padding:0 1rem;color:#1d1d1f}
        a.bm{display:inline-block;padding:.6rem 1.1rem;border-radius:10px;background:#0d2b5c;color:#fff;text-decoration:none;font-weight:600}
        ol{padding-left:1.2rem}li{margin:.4rem 0}</style>
        <h1>TAUdo sync bookmark</h1>
        <p><a class="bm" href="\(bookmarkletURL(key: key))">TAUdo sync</a></p>
        <ol><li>Drag the button above onto your bookmarks bar. Show the bar with ⇧⌘B if it's hidden.</li>
        <li>Open Moodle and log in.</li>
        <li>Click <b>TAUdo sync</b>. Allow the browser to open TAUdo.</li></ol>
        <p>The bookmark is tied to this Mac's TAUdo, so other pages can't send it data. Don't share it.</p>
        <p>TAUdo then gets your calendar link and learns which assignments you've submitted. Click it again any time to update submissions; deadlines refresh on their own.</p>
        """
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TAUdo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("TAUdo sync bookmark.html")
        try? html.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}
