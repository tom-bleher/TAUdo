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
        /// Moodle event IDs of assignment deadlines whose page says "submitted" (bookmark version 4 and up).
        /// nil if they couldn't be checked: then nothing counts as submitted.
        var submitted: [Int]?
        /// Moodle event ID → its activity page, from Moodle's calendar.
        var links: [String: String]?
        /// Course shortname → full name, from Moodle's calendar.
        var courses: [String: String]?
        /// Set when the bookmark was clicked on a course page and you chose to download its files.
        var download: Download?
        /// Course shortname → its Panopto recordings as [name, viewer URL]. Only courses whose Panopto block answered.
        var recordings: [String: [[String]]]?
        /// Bookmark version: 2 and up send recordings, 4 and up confirmed submissions. nil before version 2.
        var v: Int?
        /// Milliseconds after the click when each part of the sync finished (link, submissions, panopto, download).
        var took: [String: Int]?

        struct Download: Decodable {
            var courseID: Int
            var name: String
            var sections: [String: String]?
            var count: Int
        }

        /// The activity links that are pages of `host`'s Moodle activities, by Moodle event ID.
        func validLinks(host: String) -> [String: String] {
            (links ?? [:]).filter { id, s in
                guard Int(id) != nil, let u = URL(string: s), u.scheme == "https", u.host == host else { return false }
                return u.path.contains("/mod/")
            }
        }

        /// The recordings that are Panopto viewer links, by course.
        var validRecordings: [String: [Recording]] {
            (recordings ?? [:]).mapValues { list in
                list.prefix(300).compactMap { p in
                    guard p.count == 2, let url = URL(string: p[1]) else { return nil }
                    let r = Recording(name: p[0].trimmingCharacters(in: .whitespacesAndNewlines), url: url)
                    return Recordings.valid(r) ? r : nil
                }
            }
        }

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
        p.submitted = p.submitted.map { Array($0.prefix(2000)) }
        p.links = p.links.map { Dictionary(uniqueKeysWithValues: $0.prefix(2000).map { ($0.key, $0.value) }) }
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
      const cid = Number(M.cfg.courseId || 0);
      // Ask before the slow part, so the question doesn't wait for it.
      const wantDownload = /\/course\/view\.php$/.test(location.pathname) && cid > 1 && confirm(__ASK__);
      // A badge with TAUdo's logo while it works: the three circles light up in turn, and the check circle gets its
      // check when done. In a shadow root, so Moodle's styles can't reach it.
      const ui = (() => {
        const host = document.createElement("div");
        host.style.cssText = "all:initial;position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:2147483647";
        const root = host.attachShadow({mode: "open"});
        root.innerHTML = `<style>
          .b{display:flex;align-items:center;gap:12px;padding:10px 20px 10px 16px;border-radius:999px;background:#0d2b5c;color:#fff;
            font:500 14px/1.25 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;white-space:nowrap;
            box-shadow:0 12px 32px rgba(13,43,92,.35),0 2px 6px rgba(0,0,0,.18);
            opacity:0;transform:translateY(-14px) scale(.96);transition:opacity .25s,transform .4s cubic-bezier(.2,.9,.3,1.25)}
          .b.in{opacity:1;transform:none}
          svg{height:26px;width:auto;flex:none;overflow:visible}
          .p{fill:#fff;animation:pulse 1.2s ease-in-out infinite}
          .p2{animation-delay:.2s}.p3{animation-delay:.4s}
          @keyframes pulse{0%,100%{opacity:.28}45%{opacity:1}}
          .ck{fill:none;stroke:#0d2b5c;stroke-width:5.2;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:27;stroke-dashoffset:27}
          .done .p{animation:none;opacity:1}
          .done .ck{stroke-dashoffset:0;transition:stroke-dashoffset .45s .15s ease-out}
          .done .p1{transform-box:fill-box;transform-origin:center;animation:pop .5s ease-out}
          @keyframes pop{40%{transform:scale(1.18)}}
          @media (prefers-reduced-motion:reduce){.p{animation:none;opacity:1}.b{transition:opacity .2s}.done .p1{animation:none}}
        </style>
        <div class="b" dir="__DIR__">
          <svg viewBox="476.8 -88.6 119 41.7" aria-hidden="true"><g transform="scale(1,-1)">
            <ellipse class="p p1" cx="496.1422" cy="67.752" rx="18.3725" ry="17.947"/>
            <path class="ck" d="M487.691 67.034L493.937 60.932L504.961 74.213"/>
            <path class="p p2" transform="translate(553.7148 70.1595)" d="__RING0__"/>
            <g class="p p3"><path transform="translate(589.4198 66.2591)" d="__RING1__"/><path transform="translate(566.9156 56.8448)" d="__RING2__"/><path transform="translate(569.6835 80.1447)" d="__RING3__"/></g>
          </g></svg>
          <span class="t"></span>
        </div>`;
        document.body.appendChild(host);
        const b = root.querySelector(".b"), t = root.querySelector(".t");
        requestAnimationFrame(() => requestAnimationFrame(() => b.classList.add("in")));
        return {
          say: s => { t.textContent = s; },
          done: s => {
            t.textContent = s; b.classList.add("done");
            setTimeout(() => { b.classList.remove("in"); setTimeout(() => host.remove(), 450); }, 2400);
          },
        };
      })();
      ui.say(__GATHER__);
      // Milliseconds each part took, sent along so slow syncs can be traced.
      const t0 = performance.now(), took = {};
      const timed = (k, p) => p.then(v => { took[k] = Math.round(performance.now() - t0); return v; });
      // nosessionupdate: these reads needn't touch the session record.
      const service = base + "/lib/ajax/service.php?nosessionupdate=1&sesskey=" + encodeURIComponent(sesskey);
      const ajax = async (calls, signal) => (await fetch(service, {
        method: "POST", credentials: "include", headers: {"Content-Type": "application/json"}, signal,
        body: JSON.stringify(calls.map((c, i) => ({index: i, methodname: c[0], args: c[1]})))})).json();
      const courses = {};
      // Moodle runs one request per session at a time (session lock). Panopto's block lets go of the lock before asking
      // Panopto, so it starts first and its waiting overlaps the rest.
      // Each course's recordings come from its Panopto block (newer versions answer with data, older ones with the
      // block's HTML); a course without the block just errors. Whatever hasn't answered within the time limit waits
      // for the next click (TAUdo keeps each course's last list).
      const recordings = {};
      const panoptoCourse = async c => {
        const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
        try {
          const [x] = await ajax([["block_panopto_get_content", {courseid: c.id}]], ctl.signal);
          if (!x || x.error || x.data == null) return;
          let items = [];
          if (typeof x.data === "string") {
            const doc = new DOMParser().parseFromString(x.data, "text/html");
            items = [...doc.querySelectorAll('a[href*="Viewer.aspx"]')].map(a => [a.textContent.trim(), a.href]);
          } else {
            items = [...(x.data.recordings || []), ...(x.data.morerecordings || [])].map(s => [String(s.name || "").trim(), s.viewerurl]);
          }
          items = items.filter(i => i[0] && /^https:\/\//.test(i[1] || ""));
          if (items.length) recordings[c.shortname] = items;
        } catch (e) {} finally { clearTimeout(t); }
      };
      const panopto = async () => {
        try {
          const [en] = await ajax([["core_course_get_enrolled_courses_by_timeline_classification", {classification: "inprogress", limit: 0, offset: 0, sort: "fullname"}]]);
          const list = en && !en.error && en.data && en.data.courses ? en.data.courses : [];
          list.forEach(c => { if (c.shortname) courses[c.shortname] = c.fullname || c.shortname; });
          const todo = list.filter(c => c.id && c.shortname).slice(0, 20);
          await Promise.race([Promise.all(todo.map(panoptoCourse)), new Promise(ok => setTimeout(ok, 10000))]);
        } catch (e) {}
      };
      // Which assignments are submitted. An assignment leaves Moodle's to-do list once it's submitted, but also once its
      // completion condition is met (e.g. "view"), so each one that left the list is confirmed on its own page.
      // The to-do list query is one of the few that doesn't hold the session lock. Nothing confirmed: null.
      // Moodle's calendar also gives each event's activity page, which TAUdo opens from a deadline or cube.
      let submitted = null;
      const links = {};
      const submissions = async () => {
        try {
          const LIMIT = 50;
          // Events due from two weeks ago (earlier ones were seen on earlier clicks) to two months ahead.
          const since = Math.floor(Date.now() / 1000) - 14 * 86400;
          const months = [], d = new Date(since * 1000), end = new Date(Date.now() + 60 * 86400000);
          // Midnight on the 1st, so a daylight saving change can't push the last month past `end`.
          d.setDate(1); d.setHours(0, 0, 0, 0);
          while (d <= end) { months.push([d.getFullYear(), d.getMonth() + 1]); d.setMonth(d.getMonth() + 1); }
          const [[pending], views] = await Promise.all([
            // From `since` too: older overdue items would otherwise fill the list's 50 places.
            ajax([["core_calendar_get_action_events_by_timesort", {timesortfrom: since, limitnum: LIMIT}]]),
            ajax(months.map(([y, m]) => ["core_calendar_get_calendar_monthly_view", {year: y, month: m, courseid: 1, day: 1}]))]);
          const events = [];
          for (const v of views) {
            if (!v || v.error) continue;
            for (const w of v.data.weeks || []) for (const day of w.days || []) for (const e of day.events || []) {
              if (e.url) links[e.id] = e.url;
              events.push(e);
            }
          }
          if (!pending || pending.error || !pending.data || views.some(v => !v || v.error)) return;
          const evs = pending.data.events || [];
          const pendingIDs = new Set(evs.map(e => e.id));
          // A cut-off list may have dropped some of the deadlines due at its last moment: check only before it.
          const until = evs.length >= LIMIT ? Math.max(...evs.map(e => e.timesort || e.timestart)) : Infinity;
          const check = new Map();
          for (const e of events) {
            if (e.modulename === "assign" && e.eventtype === "due" && e.url && e.timestart >= since && e.timestart < until
                && !pendingIDs.has(e.id)) check.set(e.id, e.url);
          }
          const found = [], todo = [...check];
          const worker = async () => {
            while (todo.length) {
              const [id, url] = todo.pop();
              try {
                const html = await (await fetch(url, {credentials: "include"})).text();
                if (/\bsubmissionstatussubmitted\b/.test(html)) found.push(id);
              } catch (e) {}
            }
          };
          await Promise.all([worker(), worker(), worker()]);
          submitted = found;
        } catch (e) {}
      };
      // The calendar link. Moodle's export form needs only the session key and its form marker, so post it directly;
      // fall back to reading the form first if that didn't give a link.
      const exportLink = async () => {
        const find = html => { const m = html.match(/https?:\/\/[^"'<>\s]+calendar\/export_execute\.php\?[^"'<>\s]+/i); return m ? m[0].replace(/&amp;/g, "&") : null; };
        const post = async fields => {
          const fd = new URLSearchParams(fields);
          fd.set("events[exportevents]", "all"); fd.set("generateurl", "1");
          if (!fd.has("period[timeperiod]")) fd.set("period[timeperiod]", "recentupcoming");
          return find(await (await fetch(base + "/calendar/export.php", {method: "POST", credentials: "include",
            headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: fd.toString()})).text());
        };
        try {
          const direct = await post({sesskey, _qf__core_calendar_export_form: "1", "period[timeperiod]": "custom"});
          if (direct) return direct;
          const doc = new DOMParser().parseFromString(await (await fetch(base + "/calendar/export.php", {credentials: "include"})).text(), "text/html");
          const form = doc.querySelector('form[action*="export.php"]') || doc.querySelector("form.mform");
          if (!form) return null;
          const fields = {};
          form.querySelectorAll('input[type="hidden"]').forEach(el => { if (el.name) fields[el.name] = el.value; });
          fields["period[timeperiod]"] = form.querySelector('input[name="period[timeperiod]"][value="custom"]') ? "custom" : "recentupcoming";
          return await post(fields);
        } catch (e) { return null; }
      };
      const [, , exportURL] = await Promise.all([timed("panopto", panopto()), timed("submissions", submissions()), timed("link", exportLink())]);
      let download = null;
      if (wantDownload) {
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
          ui.say(__FILES__.replace("{n}", 0).replace("{total}", "…"));
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
              ui.say(__FILES__.replace("{n}", ++done).replace("{total}", todo.length));
            }
          };
          await Promise.all([worker(), worker(), worker()]);
        }
        download = {courseID: cid, name, sections, count};
        took.download = Math.round(performance.now() - t0);
      }
      ui.done(download ? __SENT__.replace("{n}", download.count) : __DONE__);
      const payload = {v: 4, key: "__KEY__", base, exportURL, submitted, links, courses, download, recordings, took};
      // TAUdo takes up to 200 kB: past that, leave out the longest recording lists (TAUdo keeps each course's last one).
      const big = Object.keys(recordings).sort((a, b) => recordings[b].length - recordings[a].length);
      while (big.length && new Blob([JSON.stringify(payload)]).size > 190000) delete recordings[big.shift()];
      location.href = "taudo://sync?d=" + encodeURIComponent(JSON.stringify(payload));
    })();
    """#

    /// The bookmark for `base` (your Moodle, e.g. https://moodle.tau.ac.il), carrying your sync key.
    static func bookmarkletURL(key: String, base: String) -> String {
        let ask = String(localized: "TAUdo: download all files from this course to your course folder?")
        let login = String(localized: "TAUdo: open Moodle and log in first, then click this bookmark again.")
        let js = { (s: String) in (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\"" }
        let base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let origin = URL(string: base).flatMap { u in u.host.map { "\(u.scheme ?? "https")://\($0)" + (u.port.map { ":\($0)" } ?? "") } } ?? base
        let gather = String(localized: "Gathering from Moodle…")
        let done = String(localized: "Done · opening TAUdo")
        let files = String(localized: "Downloading files {n}/{total}", comment: "Keep {n} and {total} as they are")
        let sent = String(localized: "{n} files on their way · opening TAUdo", comment: "Keep {n} as it is")
        var code = bookmarkletSource.replacingOccurrences(of: "__KEY__", with: key)
            .replacingOccurrences(of: "__GATHER__", with: js(gather)).replacingOccurrences(of: "__DONE__", with: js(done))
            .replacingOccurrences(of: "__FILES__", with: js(files)).replacingOccurrences(of: "__SENT__", with: js(sent))
            .replacingOccurrences(of: "__DIR__", with: Lang.isHebrew ? "rtl" : "ltr")
            .replacingOccurrences(of: "__ORIGIN__", with: js(origin)).replacingOccurrences(of: "__BASE__", with: js(base))
            .replacingOccurrences(of: "__ASK__", with: js(ask)).replacingOccurrences(of: "__LOGIN__", with: js(login))
        for (i, ring) in Logo.ringPathData.enumerated() { code = code.replacingOccurrences(of: "__RING\(i)__", with: ring) }
        code = code.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-_.!~*'()")
        return "javascript:" + code.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    /// Writes a small page with the draggable bookmark and opens it in the default browser.
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
        <p>TAUdo מקבל את קישור היומן ולומד אילו מטלות כבר הגשתם ואילו הקלטות יש ב־Panopto לכל קורס. אפשר ללחוץ שוב בכל עת כדי לעדכן; מועדי ההגשה מתעדכנים מעצמם.</p>
        <p><b>הורדת חומרי קורס:</b> לחיצה על הסימנייה בדף של קורס מציעה להוריד את כל הקבצים שלו. TAUdo מסדר אותם בתיקיית הקורס, לפי נושאים. ייתכן שהדפדפן יבקש אישור להורדת כמה קבצים.</p>
        """ : """
        <!doctype html><html lang="en"><meta charset="utf-8"><title>TAUdo sync bookmark</title>\(style)
        <h1>TAUdo sync bookmark</h1>
        <div class="drag"><a class="bm" href="\(link)">TAUdo sync</a><span>Drag this button onto the bookmarks bar at the top of the window</span></div>
        <ol><li>Drag the button onto your bookmarks bar. Show the bar with ⇧⌘B if it's hidden.</li>
        <li>Open Moodle and log in.</li>
        <li>Click <b>TAUdo sync</b>. Allow the browser to open TAUdo.</li></ol>
        <p>The bookmark is tied to this Mac's TAUdo, so other pages can't send it data. Don't share it.</p>
        <p>TAUdo then gets your calendar link and learns which assignments you've submitted and which recordings each course has on Panopto. Click it again any time to update; deadlines refresh on their own.</p>
        <p><b>Course materials:</b> click the bookmark on a course page to download all its files. TAUdo files them into the course folder, by section. Your browser may ask to allow multiple downloads.</p>
        """
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TAUdo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("TAUdo sync bookmark.html")
        try? html.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}
