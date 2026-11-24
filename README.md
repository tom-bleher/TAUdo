<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo.png" width="280" alt="TAUdo logo">
  </picture>
</p>

# TAUdo

A macOS menu bar companion for Tel Aviv University students. It shows your Moodle deadlines and your progress in each course, and reminds you before things are due. Hebrew by default, with an English option.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/panel-due-he-dark.png">
    <img src="assets/screenshots/panel-due-he.png" width="380" alt="Due tab: upcoming deadlines and exams, grouped by when they're due">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/panel-courses-he-dark.png">
    <img src="assets/screenshots/panel-courses-he.png" width="380" alt="Courses tab: lectures, recitations and homework per course, and where the class is">
  </picture>
</p>

## Privacy

- TAUdo runs on your Mac. There is no TAUdo server and no account. It connects to:
  - Moodle, for your calendar export link.
  - [arazim-project.com](https://arazim-project.com), to download the semester's public course list for exam dates. Nothing about you is sent.
  - GitHub, to check for updates.
- With calendar sync on, your deadlines go into the calendar you pick, and so to iCloud or Google if that calendar lives there. *Subscribe in Google Calendar…* gives Google your Moodle calendar link.
- It never sees your TAU password or your browser session.
  - Deadlines come from Moodle's calendar export link.
  - Submission status and course downloads come from the bookmark, which runs in your own logged-in browser tab.
- Your data stays in `~/Library/Application Support/TAUdo/state.json`, readable only by you, since the calendar link is a key to your Moodle calendar.
- The bookmark carries a secret tied to your copy of TAUdo, so other web pages can't send it data.

## How the Moodle parts work

| What | How | Needs |
|---|---|---|
| Deadlines | Moodle's iCal export (`calendar/export_execute.php`), fetched hourly, on wake, and when you open the panel | Only the link |
| Submitted assignments | The bookmark compares assignment due events with Moodle's to-do list (`core_calendar_get_action_events_by_timesort`). An assignment no longer on the list counts as submitted | A click on the bookmark while logged in |
| Course files | Moodle's *Download course content* zip if the course allows it. Otherwise `core_courseformat_get_state`, which gives files as `mod/resource/view.php?redirect=1` and folders as `download_folder.php` zips, plus files linked in section text | A click on the bookmark on the course page |

Some details:
- Homework deadlines are matched to cubes by course and number (`תרגיל בית 3`, `הגשת שיעורי בית 3`, `HW 3`, `Problem Set 3`, …).
- Moodle courses are linked to your courses by name, or by the TAU course code if it appears in the course's files.
- Moodle's export only looks back a few days, so TAUdo keeps this semester's past events.
- Moodle's to-do list also drops activities you marked complete by hand. Untick a deadline to override; TAUdo never re-applies the same report.
- TAU Moodle opens in guest mode, and guests get a session too. The bookmark only runs on pages with a logout link, and TAUdo ignores guest export links (`userid=1`).

## License

The code is under the [MIT License](LICENSE). The ring shapes in the logo come from Tel Aviv University's logo and are not covered by it.

TAUdo is not affiliated with or endorsed by Tel Aviv University. The TAU logo and name are the university's trademarks.
