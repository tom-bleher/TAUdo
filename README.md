# TAUdo

A macOS menu bar companion for TAU students. It combines the cube progress tracker (`track.html`) with the Moodle calendar sync (`../tau-moodle-calendar`).

- **Menu bar**: the next open deadline and time left, e.g. `Methods HW 8 · 2d`, plus an overdue count. Deadlines you've done, or that Moodle reports as submitted, drop out.
- **Panel**: open deadlines and exams, a two-week strip, and a cube grid per course (Lecture / Recitation / Homework). Each row shows a **class marker** (where the class is) and how far ahead (+) or behind (−) of the class you are.
- **Pace per course**:
  - *With class*: anything the class has covered that you haven't is outlined orange.
  - *Self-study*: you work toward a finish date instead, and the class marker shows the class catching up.
- **Moodle, in your own browser**: "Open Moodle in browser" opens Moodle's export page. Log in, click *Get calendar URL* and copy the link: TAUdo picks it up from the clipboard. It only checks the clipboard for 15 minutes after you click, and only accepts a Moodle export link. Deadlines then refresh on their own: at launch, every hour, after wake, and when you open the panel if the data is older than 10 minutes. Homework deadlines link to the matching homework cube by course and number (`תרגיל בית 3`, `HW 3`, `Problem Set 3`, …).
- **TAUdo sync bookmark** (optional): click it on any signed-in Moodle page to send the link, course names and your submitted assignments to TAUdo (via `taudo://sync`). It carries a secret tied to this install, so other pages can't send it data.
- **Your files**: with one folder per course in the coursework folder (Settings › General › Files), ⌘-click or right-click a cube to open its lecture recording (`videos/…/03 - ….mkv`, `שיעור 03.mp4`), its pset folder (`psets/pset7`) or its recitation (`recitations/rec3.pdf`). A dot marks cubes that have a file.
- **Course linking**: Moodle courses link to your courses automatically when the TAU course code appears in the course's files, or when Moodle's course name contains your course's name. Anything left over shows a one-click "Link to…" prompt in the panel.
- **Reminders** have a *Mark done* button.
- **Apple Calendar** (optional): mirrors Moodle into its own calendar, with ✅ / ⬜ / 🔴 status in titles. Alerts are only set on deadlines that are still open.
- **Exams**: add exam dates by hand in Settings › Exams, since TAU exam dates are usually not on Moodle.

## Use

Cubes: click to cycle through *not done → done → to do → revisit → skipped*. ⌥-click a cube to say "the class is here"; the class marker keeps advancing from that point. Right-click a cube for more options.

Settings › Courses: map each course to its Moodle course, and set the pace, rows, and sessions per week. To bring over progress from `track.html`, use Settings › General › Import.

## Build

Requires Xcode and `xcodegen` (`brew install xcodegen`).

```sh
scripts/build.sh test    # run unit tests, then build ./TAUdo.app (Release)
open TAUdo.app
scripts/make_icon.sh     # regenerate assets/AppIcon.icns from Sources/UI/Logo.swift
```

Debug flags: `--demo` uses sample data in memory and never touches your saved state. `--preview` also opens the panel in a normal window.

State is stored in `~/Library/Application Support/TAUdo/state.json` (mode 600, because the export link is a token for your calendar).

## How the Moodle parts work

TAUdo never sees your browser session or password.

| What | How | Needs |
|---|---|---|
| Deadlines | Moodle's iCal export link (`calendar/export_execute.php`), fetched automatically | Only the link; no Moodle session |
| Export link | Copied from Moodle › Export calendar (clipboard pickup), or sent by the bookmark, which submits Moodle's export form in your tab | One login in your browser |
| Submitted? | The bookmark asks Moodle's AJAX API for assignment due events and for which ones are still on your to-do list (`core_calendar_get_action_events_by_timesort`). Anything no longer on the list counts as submitted | A click on the bookmark while logged in |

Moodle's to-do list also drops activities whose completion you ticked by hand, so those count as submitted too. Untick a cube to override; TAUdo never re-applies the same report.

Moodle's export only looks back a few days. TAUdo therefore keeps past events from the current semester, so past homework stays linked to its cube.

If the saved state can't be read, TAUdo keeps it as `state.unreadable-<date>.json` and starts fresh. It never overwrites the file silently.

TAU Moodle opens in guest mode, and guests also get a session key. The bookmark only runs on pages that have a logout link, and TAUdo ignores export links that belong to the guest user (`userid=1`). Links from the bookmark are only accepted for the configured Moodle host.

## Logo

Based on TAU's logo:
- **App icon:** the logo's solid circle with the torch emblem, with the bowl drawn as a check mark.
- **Menu bar:** the logo's three circles, read as a checklist: done ✓, in progress (heavy ring), to do (thin rings).

It's for personal use, since the TAU logo is the university's trademark. To regenerate the icon, run `scripts/make_icon.sh`.

## Layout

```
Sources/Core      ICS parser, Hebrew/English classifier, models, pacing logic (unit-tested, no UI)
Sources/Services  AppModel (state + sync loop), MoodleFeed, MoodleConnect (browser link + bookmark), CalendarSync (EventKit), Notifier
Sources/UI        Menu bar app, panel, course cubes, settings, logo
Tests             XCTest for Core and the Moodle link/bookmark handling
```
