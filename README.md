<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo.png" width="280" alt="TAUdo logo">
  </picture>
</p>

# TAUdo

A macOS menu bar companion for Tel Aviv University students. It shows your Moodle deadlines and your progress in each course, and reminds you before things are due. Hebrew by default, with an English option.

**עוזר לסטודנטים באוניברסיטת תל אביב, בשורת התפריטים של ה־Mac: מועדי הגשה מ־Moodle, מעקב התקדמות בקורסים ותזכורות.**

<p align="center">
  <img src="assets/screenshots/panel-due-he.png" width="380" alt="Due tab">
  <img src="assets/screenshots/panel-courses-he.png" width="380" alt="Courses tab">
</p>

## Features

- **The next deadline in the menu bar**, with the time left (e.g. `חשבון תרגיל 4 · 22 שע׳`). A deadline disappears once you've submitted it.
- **Due tab:** every upcoming Moodle deadline and exam, grouped into today, tomorrow, the next 7 days and later. Tick one when you've handed it in. Overdue items are hidden unless you ask for them.
- **Courses tab:** a card of cubes per course, one row each for lectures, recitations and homework. A blue marker shows where the class is, and `+3` / `−2` shows how far ahead or behind it you are.
  - *With class* or *self-study* pace per course. For self-study you set a finish date, and the marker shows the class catching up.
  - Homework cubes link to their Moodle deadlines and turn orange or red as the deadline nears or passes.
  - With a folder per course, ⌘-click (or right-click) a cube to open its lecture recording, pset folder or recitation file.
- **Alerts:**
  - Reminders before each open deadline, with a *Mark done* button.
  - An alert when Moodle posts a new deadline or moves one.
  - An optional morning summary of what's due today and tomorrow.
- **Download a course's files:** click the TAUdo bookmark on a Moodle course page. TAUdo saves every file into the course folder, sorted by section.
- **Apple Calendar and Google Calendar** (optional): mirrors Moodle into a calendar of its own, or into any calendar you pick. Its alerts reach your iPhone through iCloud.
  - For Google, add your Google account in System Settings › Internet Accounts and pick one of its calendars. Or use *Subscribe in Google Calendar…*, which subscribes Google to the Moodle link itself (Moodle's titles, refreshed by Google every few hours).
- **Exam dates** (מועד א and ב) are filled in from [Arazim](https://arazim-project.com) for each Moodle course. Other dates that aren't on Moodle can be added by hand.

## Install

Requires macOS 14 or later on a Mac with Apple silicon.

1. Download `TAUdo-<version>.dmg` from [Releases](../../releases), open it and drag TAUdo into the empty circle (Applications).
2. Open TAUdo. It isn't notarized by Apple, so macOS blocks it the first time: go to System Settings › Privacy & Security, click *Open Anyway* next to TAUdo, and confirm.
   After that TAUdo updates itself: Settings › General › Updates.
3. The welcome window walks you through the rest:
   - **Connect Moodle:** TAUdo opens Moodle's *Export calendar* page in your browser. Log in, click the button to get the calendar URL, and copy it. TAUdo picks it up from the clipboard.
   - **Choose your courses:** your Moodle courses are listed, and TAUdo creates the ones you pick, already linked to Moodle.
   - **Course folder** (optional) and **notifications**.

Optional: from the ⋯ menu, choose *Install sync bookmark…* and drag the button to your bookmarks bar. Clicking it on Moodle tells TAUdo which assignments you've already submitted. On a course page, it also offers to download the course's files.

To uninstall, quit TAUdo, delete the app and delete `~/Library/Application Support/TAUdo`.

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

## Development

Requires Xcode and XcodeGen (`brew install xcodegen`). Releasing also needs uv and the GitHub CLI (`brew install uv gh`).

```sh
scripts/build.sh test            # unit tests, then ./TAUdo.app (Release)
scripts/check_translations.sh    # every UI string has a Hebrew translation
scripts/make_icon.sh             # app icon, logo and DMG images from Sources/UI/Logo.swift
scripts/release.sh [--publish]   # DMG + signed Sparkle appcast in dist/; --publish makes the GitHub release
```

| Flag | Effect |
|---|---|
| `--demo` | Sample data in memory; your saved state is never touched |
| `--snapshot <dir>` | With `--demo`, renders the panel, settings and welcome window to PNGs offscreen (pass `-language he -AppleLanguages "(he)"` or `en` too) |
| `-language en -AppleLanguages '(en)'` | English UI |
| `--settings` | Opens the Settings window at launch |
| `--dark` | Dark appearance |

```
Sources/Core      Moodle iCal parser, Hebrew/English deadline classifier, models, pacing, alerts, download filing (unit-tested)
Sources/Services  App state and sync loop, Moodle link and bookmark, Apple Calendar, notifications, language
Sources/UI        Menu bar panel, course cubes, settings, welcome window, logo
Sources/he.lproj  Hebrew strings
Tests             XCTest
```

## Logo

The logo is a check mark in a solid circle, followed by TAU's heavy ring and interlocking rings. The three circles read as a checklist (done, in progress, to do). The app icon is the check circle, and the installer has you drag it into its place in the logo.

TAUdo is not affiliated with or endorsed by Tel Aviv University. The TAU logo and name are the university's trademarks.

## License

The code is under the [MIT License](LICENSE). The ring shapes in the logo come from Tel Aviv University's logo and are not covered by it.
