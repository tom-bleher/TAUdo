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
        /// Set when the bookmark was clicked on a course page and you chose to download its files.
        var download: Download?

        struct Download: Decodable {
            var courseID: Int
            var name: String
            var sections: [String: String]?
            var count: Int
        }

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
            // Only read the clipboard when it holds a web link, so copied passwords are never read.
            guard await isWebLink(pb) else { continue }
            if let s = pb.string(forType: .string), s.contains("export_execute.php"), let link = exportLink(s, host: host) { return link }
        }
        return nil
    }

    /// Asks macOS whether the clipboard holds a URL without reading it (macOS 15.4+), so copied passwords are
    /// never read and no clipboard-privacy prompt appears. Older systems have no such prompt: read as before.
    private static func isWebLink(_ pb: NSPasteboard) async -> Bool {
        guard #available(macOS 15.4, *) else { return true }
        return (try? await pb.detectedPatterns(for: [\.probableWebURL]).contains(\.probableWebURL)) ?? false
    }

    /// The bookmarklet: runs in a signed-in Moodle tab, submits Moodle's own export form for the link,
    /// asks Moodle's AJAX API which assignment deadlines are still to do, and hands both to TAUdo.
    static let bookmarkletSource = #"""
    (async () => {
      // Only on your Moodle: another page could imitate Moodle's page objects (even URL or JSON), not its address.
      if (location.origin !== __ORIGIN__) { alert(__LOGIN__); return; }
      const base = __BASE__;
      const M = window.M;
      if (!M || !M.cfg || !M.cfg.sesskey || !document.querySelector('a[href*="/login/logout.php"]')) {
        alert(__LOGIN__); return;
      }
      const sesskey = M.cfg.sesskey;
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
      let download = null;
      const cid = Number(M.cfg.courseId || 0);
      if (/\/course\/view\.php$/.test(location.pathname) && cid > 1 && confirm(__ASK__)) {
        const box = document.createElement("div");
        box.style.cssText = "position:fixed;top:16px;left:50%;transform:translateX(-50%);z-index:2147483647;background:#0d2b5c;color:#fff;padding:10px 16px;border-radius:10px;font:14px system-ui;box-shadow:0 8px 24px rgba(0,0,0,.3)";
        document.body.appendChild(box);
        const say = t => { box.textContent = "TAUdo: " + t; };
        const save = (blob, name) => {
          const a = document.createElement("a");
          a.href = URL.createObjectURL(blob);
          a.download = "TAUdo__" + cid + "__" + name.replace(/[\/\\:]/g, "-");
          document.body.appendChild(a); a.click();
          setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 120000);
        };
        const name = ((document.querySelector(".page-header-headings h1") || document.querySelector("h1") || {}).textContent || document.title).trim();
        const sections = {};
        let count = 0;
        const whole = document.querySelector('[data-downloadcourse], a[href*="/course/downloadcontent.php"]');
        if (whole && M.cfg.courseContextId) {
          say("…");
          try {
            const fd = new FormData(); fd.append("sesskey", sesskey);
            const r = await fetch(base + "/course/downloadcontent.php?contextid=" + M.cfg.courseContextId + "&download=1", {method: "POST", body: fd, credentials: "include"});
            if (r.ok && !/text\/html/.test(r.headers.get("content-type") || "")) { save(await r.blob(), "all__course.zip"); count = 1; }
          } catch (e) {}
        }
        if (!count) {
          const items = [];
          try {
            const [st] = await ajax([["core_courseformat_get_state", {courseid: cid}]]);
            if (st && !st.error) {
              const state = JSON.parse(st.data);
              const secs = {};
              for (const sec of state.section || []) { secs[sec.id] = sec.number; sections[sec.number] = sec.title || ""; }
              for (const cm of state.cm || []) {
                if (!cm.uservisible) continue;
                const n = secs[cm.sectionid] ?? cm.sectionnumber ?? 0;
                if (cm.module === "resource") items.push({u: base + "/mod/resource/view.php?id=" + cm.id + "&redirect=1", s: n});
                if (cm.module === "folder") items.push({u: base + "/mod/folder/download_folder.php?id=" + cm.id, s: n, zip: cm.name});
              }
            }
          } catch (e) {}
          if (!items.length) {
            document.querySelectorAll('li[data-for="cmitem"].modtype_resource, li[data-for="cmitem"].modtype_folder').forEach(li => {
              const sec = li.closest('[data-for="section"]'); const n = sec ? Number(sec.dataset.number || 0) : 0;
              const id = li.dataset.id; if (!id) return;
              if (li.classList.contains("modtype_resource")) items.push({u: base + "/mod/resource/view.php?id=" + id + "&redirect=1", s: n});
              else items.push({u: base + "/mod/folder/download_folder.php?id=" + id, s: n, zip: (li.querySelector("[data-activityname]") || {}).dataset?.activityname || "folder"});
            });
          }
          document.querySelectorAll('[data-for="section"]').forEach(sec => {
            const n = Number(sec.dataset.number || 0);
            if (sections[n] === undefined) sections[n] = ((sec.querySelector(".sectionname") || {}).textContent || "").trim();
          });
          document.querySelectorAll('a[href*="/pluginfile.php/"]').forEach(a => {
            if (!a.href.startsWith(base + "/")) return;
            const sec = a.closest('[data-for="section"]');
            items.push({u: a.href, s: sec ? Number(sec.dataset.number || 0) : 0});
          });
          const seen = new Set(), todo = items.filter(i => !seen.has(i.u) && seen.add(i.u));
          let done = 0, next = 0;
          const worker = async () => {
            while (next < todo.length) {
              const it = todo[next++];
              try {
                const r = await fetch(it.u, {credentials: "include"});
                const ct = r.headers.get("content-type") || "";
                if (r.ok && !/text\/html/.test(ct)) {
                  const file = it.zip ? it.zip + ".zip" : decodeURIComponent(new URL(r.url).pathname.split("/").pop() || "file");
                  save(await r.blob(), it.s + "__" + file); count++;
                }
              } catch (e) {}
              say(++done + "/" + todo.length);
            }
          };
          await Promise.all([worker(), worker(), worker()]);
        }
        say(count ? "✓ " + count : "0");
        setTimeout(() => box.remove(), 4000);
        download = {courseID: cid, name, sections, count};
      }
      location.href = "taudo://sync?d=" + encodeURIComponent(JSON.stringify({key: "__KEY__", base, exportURL, assignIDs, pendingIDs, courses, download}));
    })();
    """#

    /// The bookmark for `base` (your Moodle, e.g. https://moodle.tau.ac.il), carrying your sync key.
    static func bookmarkletURL(key: String, base: String) -> String {
        let ask = String(localized: "TAUdo: download all files from this course to your course folder?")
        let login = String(localized: "TAUdo: open Moodle and log in first, then click this bookmark again.")
        let js = { (s: String) in (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\"" }
        let base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let origin = URL(string: base).flatMap { u in u.host.map { "\(u.scheme ?? "https")://\($0)" + (u.port.map { ":\($0)" } ?? "") } } ?? base
        let code = bookmarkletSource.replacingOccurrences(of: "__KEY__", with: key)
            .replacingOccurrences(of: "__ORIGIN__", with: js(origin)).replacingOccurrences(of: "__BASE__", with: js(base))
            .replacingOccurrences(of: "__ASK__", with: js(ask)).replacingOccurrences(of: "__LOGIN__", with: js(login)).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-_.!~*'()")
        return "javascript:" + code.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    /// Writes a small page with the draggable bookmark and opens it in the default browser.
    /// Google Calendar's "add this calendar?" prompt for an https calendar link (undocumented but long-standing:
    /// `calendar/render?cid=` with the link as webcal://, fully percent-encoded so its query survives).
    static func googleSubscribeURL(_ link: String) -> URL? {
        guard link.hasPrefix("https://"), link.count > 8 else { return nil }
        let webcal = "webcal://" + link.dropFirst("https://".count)
        guard let cid = webcal.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) else { return nil }
        return URL(string: "https://calendar.google.com/calendar/render?cid=" + cid)
    }

    static func openBookmarkletPage(key: String, base: String) {
        let style = """
        <style>:root{color-scheme:light dark}
        body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:560px;margin:4rem auto;padding:0 1.25rem;color:#1d1d1f;background:#fff}
        h1{font-size:1.6rem;margin:0 0 1.25rem}p{color:#424245}ol{padding-inline-start:1.2rem}li{margin:.4rem 0}
        .drag{display:flex;align-items:center;gap:1rem;padding:1.25rem;border:2px dashed #b8c2d6;border-radius:14px;margin-bottom:1.5rem}
        .drag span{color:#6e6e73;font-size:.9rem}
        a.bm{flex:none;padding:.6rem 1.1rem;border-radius:10px;background:#0d2b5c;color:#fff;text-decoration:none;font-weight:600;cursor:grab}
        @media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#f5f5f7}p{color:#c7c7cc}.drag{border-color:#48526a}.drag span{color:#98989d}a.bm{background:#3b6fd4}}
        </style>
        """
        let link = bookmarkletURL(key: key, base: base)
        let html = Lang.isHebrew ? """
        <!doctype html><html dir="rtl" lang="he"><meta charset="utf-8"><title>סימניית הסנכרון של TAUdo</title>\(style)
        <h1>סימניית הסנכרון של TAUdo</h1>
        <div class="drag"><a class="bm" href="\(link)">סנכרון TAUdo</a><span>גררו את הכפתור לסרגל הסימניות שבראש החלון</span></div>
        <ol><li>גררו את הכפתור לסרגל הסימניות (<span dir="ltr">⇧⌘B</span> מציג אותו אם הוא מוסתר).</li>
        <li>פתחו את Moodle והתחברו.</li>
        <li>לחצו על <b>סנכרון TAUdo</b> ואשרו לדפדפן לפתוח את TAUdo.</li></ol>
        <p>הסימנייה קשורה ל־TAUdo שבמחשב הזה, כך שדפים אחרים לא יכולים לשלוח לו נתונים. אל תשתפו אותה.</p>
        <p>TAUdo מקבל את קישור היומן ולומד אילו מטלות כבר הגשתם. אפשר ללחוץ שוב בכל עת כדי לעדכן הגשות; מועדי ההגשה מתעדכנים מעצמם.</p>
        <p><b>הורדת חומרי קורס:</b> לחיצה על הסימנייה בדף של קורס מציעה להוריד את כל הקבצים שלו. TAUdo מסדר אותם בתיקיית הקורס, לפי נושאים. ייתכן שהדפדפן יבקש אישור להורדת כמה קבצים.</p>
        """ : """
        <!doctype html><html lang="en"><meta charset="utf-8"><title>TAUdo sync bookmark</title>\(style)
        <h1>TAUdo sync bookmark</h1>
        <div class="drag"><a class="bm" href="\(link)">TAUdo sync</a><span>Drag this button onto the bookmarks bar at the top of the window</span></div>
        <ol><li>Drag the button onto your bookmarks bar. Show the bar with ⇧⌘B if it's hidden.</li>
        <li>Open Moodle and log in.</li>
        <li>Click <b>TAUdo sync</b>. Allow the browser to open TAUdo.</li></ol>
        <p>The bookmark is tied to this Mac's TAUdo, so other pages can't send it data. Don't share it.</p>
        <p>TAUdo then gets your calendar link and learns which assignments you've submitted. Click it again any time to update submissions; deadlines refresh on their own.</p>
        <p><b>Course materials:</b> click the bookmark on a course page to download all its files. TAUdo files them into the course folder, by section. Your browser may ask to allow multiple downloads.</p>
        """
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TAUdo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("TAUdo sync bookmark.html")
        try? html.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}
