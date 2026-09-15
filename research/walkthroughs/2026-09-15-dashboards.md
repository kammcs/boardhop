# Dashboards walkthrough — iPhone 17 and iPad Pro 13-inch, 2026-09-15

Phase D-D of research/19 (acceptance). Devices: iPhone 17 simulator
`9CB22607-F6D0-4C47-8B2D-4AC4F60A6A31` and iPad Pro 13-inch (M4)
`929DE352-434C-4CE6-BB96-5C34212741E8`, **debug** builds from `flutter run`
(consoles `iphone.log`, `iphone2.log`, `ipad.log` in the session scratchpad).
Signed in as Kelly (puremedia).

**Nothing was written anywhere.** This phase needed no writes at all — not even
in the scratch project — and the client projects were read with GETs alone.

Screenshots live in `.shots/` (gitignored) under the `dd` prefix. **No
screenshot of a client project is named here**: those were opened only to
confirm the empty-dashboard offer and that a populated Overview renders, and
only counts are reported.

**Console: no `EXCEPTION`, no `overflowed`, no `RenderFlex`, no assert** on
either device over the whole run.

The `vso.dashboards` scope Kelly granted this morning works. The app's token
was **accepted by the Dashboard API on the first try** — no sign-out, no fresh
sign-in, no 401. The D-B fallback to the Team overview on a refusal was
therefore never provoked and stays test-only.

Five defects were found on the devices and fixed here, one of them a real
service error rather than a cosmetic one. Every fix has a test.

---

## Per acceptance item (research/19 §5)

| # | Item | Verdict |
|---|---|---|
| 1 | The scratch Overview: every renderable kind, footer count, D7 taps | **pass** |
| 2 | Both simulators, light and dark, xxxL, portrait and landscape | **pass** |
| 3 | Picker: grouping, Team overview, last opened, `?dashboard=` | **pass** (favorites-first not demonstrable) |
| 4 | Team overview: six cards, focus view per chart, D15 legend | **pass** |
| 5 | Empty-dashboard offer (D1) and a populated client Overview | **pass** |
| 6 | Offline | **not demonstrable** — covered by widget tests |
| 7 | Diagnostics: Dashboard API, Analytics widget sets, the probe | **pass** |
| 8 | Search on Summary only, pill, dock, `_bleedsUnderRail` | **pass** |
| 9 | The four D-C flags, plus the y axis's round number | **pass, all fixed** |

### 1. The scratch Overview — pass (iPhone)

Dashboard `985ff75c-bdf6-4b2d-a2b0-0ef63431e6ec` ("Overview", DevOps Mobile
App Team), the 13 widgets w36 wrote. **Twelve draw, one is hidden**, and the
footer reads **"1 widget not shown in Boardhop"** — the Chart for Work Items
widget, per D2, with the singular right. Drawn, in the web's reading order:

- **Query Tile** `11`, on the settings' own blue (the `colorRules` are honoured).
- **Code Tile** DevOps Mobile App · main · `/`.
- **Build History** 19 runs · last 1d, red/green/grey bars.
- **Sprint Overview** Iteration 1, 13 not started · 5 in progress · 0 done,
  4 working days left.
- **Markdown** "Boardhop scratch", the settings string rendered as markdown.
- **Query Results** six rows then "See all 11".
- **Cumulative Flow Diagram** 9 items on the Stories today, 30 days, four bands.
- **Cycle Time** and **Lead Time**, "1 item" each (the singular is right).
- **Velocity** over 1 iteration.
- **Pull Requests** !8334 and !8336.
- **Assigned to Me** six rows then "See all 13".

`dd14-overview`, `dd15-ov-1` … `dd15-ov-4`, `dd63-fix-cfd2`, `dd64-label`.

**D7 taps, every one exercised on the device:**

| Card | Opened |
|---|---|
| Query Tile | Work items with the saved query selected as the chip (`dd19-tap-query`) |
| Query Results row | the work item |
| Build History | the **run** under the tapped bar — `boardhop-scratch` 20260913.2, with its stages (`dd22-build2`) |
| Sprint Overview | Sprint, Iteration 1, Taskboard tab (`dd23-tap-sprint`) |
| Code Tile | the repository page (`dd26-codeback`, which also shows Back returning to the dashboard) |
| Pull Requests row | PR !8334 (`dd17-tap-pr`) |
| Assigned to Me row | work item 15558 (`dd16-tap-item`) |
| any chart | the focus view (`dd29-cfd-focus2`) |

One thing to know: **a chart card opens its focus view from the title and the
caption, not from the plot area** — fl_chart takes the touch there for its own
tooltip. That is the right trade (the tooltip is the more frequent gesture) but
it is not obvious, and it is the reason `dd28-cfd-focus` shows nothing
happening.

### 2. Both devices, both themes, xxxL, both orientations — pass

- **iPhone portrait, light**: the one-column layout, cards in reading order,
  full width. `dd14-overview`.
- **iPhone dark**: every card and every chart reads correctly; the chart series
  ramp holds up. `dd32-dark-dash`, `dd33-dark-dash2`, `dd31-dark-focus`.
- **iPhone xxxL**: nothing overflows, no `RenderFlex` in the console; the axes
  thin to three gridlines and the last x label still clears the card edge.
  `dd34-xxxl`, `dd35-xxxl-2`, `dd35-xxxl-3`, `dd65-xxxl-charts`,
  `dd68-xxxl-cfd3`.
- **iPhone landscape**: the focus view puts the legend and the data list beside
  the chart (D15). `dd30-focus-landscape`.
- **iPad portrait** (1032 × 1376 pt): the **packed grid**, two 168 dp-derived
  columns wide, keeping the web's relative shape — Query Tile 1×1 and Code Tile
  1×1 side by side with Build History 1×2 beside them, Sprint Overview and
  Markdown as a pair below. The picker opens as a **centred dialog**, not a
  sheet, like the sprint picker. `dd85-ipad-overview`, `dd84-ipad-picker`,
  `dd83-ipad-dash` (the Team overview, six cards in two columns).
- **iPad landscape**: two columns with the floating glass rail on the right and
  the page **clear of it** — `_bleedsUnderRail` does not name `/dashboards`, so
  the cards stop before the rail rather than running under it.
  `dd87-ipad-landscape`.
- **iPad dark** and **iPad dark at xxxL**: every card and chart reads, cards
  grow, nothing overflows and the console is clean. `dd94-ipad-setdark`,
  `dd95-ipad-xxxl`.

**One thing to know about the iPad simulator:** Boardhop's own Appearance
setting there was pinned to **Light**, so `simctl ui … appearance dark` changes
nothing and a screenshot looks like the app ignoring the system. It was
switched to Dark for the check and **put back to Light** afterwards.

The packed grid leaves the right half of a row empty when the next widget in
reading order does not fit beside the one before it (the lower half of the
scratch Overview, where the spans w36 wrote are mostly full-width). That is D4
working as specified — the web's shape is kept rather than repacked — but it
reads sparse on a dashboard whose author never laid it out for two columns.

**One thing about `tool/shot-ios.sh` on iOS 26.5:** `simctl io … screenshot`
returns the **already rotated** frame (2622 × 1206) on a rotated simulator, so
the script's `ROT=` rotates the thumbnail a second time and the picture comes
out sideways. Taps still map correctly. Worth fixing in the tool; for this run
the landscape thumbnails were made straight from the raw frame.

### 3. The picker — pass, with one part not demonstrable

Grouped by team ("DevOps Mobile App Team" as the group header) with **Team
overview / Built into Boardhop** last and a check on the current entry.
`dd13-picker`.

- **Last opened, across a cold restart:** Team overview was picked, the app was
  killed with `simctl terminate` and relaunched, and the Dashboards view came
  back on **Team overview** rather than the default team's Overview.
  `dd42-cold`, `dd43-cold-dash`.
- **`?dashboard=` deep link:** typed into the diagnostics route opener as
  `/orgs/puremedia/projects/DevOps%20Mobile%20App/dashboards?dashboard=985ff75c-…`
  and it opened the real Overview, overriding the remembered Team overview.
  `dd45-route-typed`, `dd46-deeplink`.
- **Favorites first — not demonstrable.** Kelly has no dashboard favorited in
  puremedia, and every project here has exactly one team with exactly one
  dashboard, so there is nothing for the ordering to sort. Favoriting one would
  be a write outside the scratch project on three of the four projects and a
  write the app cannot make on the fourth. Covered by
  `test/features/dashboard_page_test.dart` instead.

### 4. The Team overview — pass (iPhone, iPad)

All six D9 cards drew on the scratch project: **sprint burndown** (Iteration 1,
18 items, ideal line and weekend bands), **work by state** (30 work items
across 3 types), **cumulative flow** (9 items on the Stories, 30 days),
**cycle and lead time** (60 days), **velocity** (1 iteration), **pipeline pass
rate** (41 %, 19 runs in 90 days, 10 failed). `dd37-pick-team`, `dd38-team2`,
`dd41-team5`.

The focus view opened from each chart and followed the orientation (D15):
legend and data list **below** in portrait, **beside** in landscape, on both
devices. `dd29-cfd-focus2`, `dd30-focus-landscape`, `dd31-dark-focus`
(iPhone); `dd88-ipad-focus-land`, `dd89-ipad-dark` (iPad, landscape and
portrait).

Cards that have nothing to draw say so rather than failing: on a project with
no dated iterations the velocity card reads "This team has no dated iterations."
and the pipeline card "No runs in the last 90 days."

### 5. The empty-dashboard offer, and a client Overview — pass (read-only)

- **Empty offer (D1).** A client project's Overview is empty, and the page shows
  the icon, "This dashboard has no widgets.", the sentence about the web, and a
  **Show the Team overview** button. Tapping it drew the Team overview for that
  team.
- **A populated client Overview**, opened once: **10 widgets, 8 drawn, 2 hidden**
  behind the footer line **"2 widgets not shown in Boardhop"** — the two Chart
  for Work Items widgets, exactly as D2 says. Velocity drew six iterations of
  real history, the query tile its number, Team Members its avatars, and the
  legacy Sprint Burndown reported "No snapshots in this period yet." for an
  iteration outside the Analytics window.
- **This is where the Burndown/Burnup defect was found** (below): both cards
  read "Bad Request" before the fix and draw their series after it.

No client screenshot is named, and no client name, title or number appears in
this document.

### 6. Offline — not demonstrable on this Mac

The Mac is on wired Ethernet and the simulator has no airplane mode, so the
offline branch stays covered by widget tests:
`test/features/dashboard_page_test.dart` (a cached dashboard opens with the
"Updated N min ago" line and a refresh failure is reported without losing it),
`test/features/dashboard_cards_test.dart` and
`test/features/dashboard_chart_cards_test.dart` (each card draws from cache
first and shows its inline error above whatever was cached), and
`test/data/dashboard_repository_test.dart` (cache-first `get`, a failure
falling back to the cached dashboard, and a 401 never masked by the cache).

The **cache-first** half was seen for real: after the cold restart the
Dashboards view came back with the remembered dashboard already drawn.

### 7. Diagnostics — pass (iPhone)

Both new checks are green **with the app's own token**:

- **Dashboard API: dashboards in puremedia/DevOps Mobile App** — "token
  ACCEPTED by the dashboard API; 1 dashboards in 225 ms; 'Overview' has 13
  widgets, Boardhop draws 12", 318 ms.
- **Analytics widget sets: work by state for puremedia/DevOps Mobile App** —
  "token ACCEPTED by analytics.dev.azure.com for WorkItems; 8 state groups
  (30 items) in 324 ms", 363 ms.
- The pre-existing **Analytics: burndown** check also ACCEPTED (4 days for
  Iteration 1 in 934 ms).

`dd03-checks`, `dd04-checks2`.

`/diagnostics/dashboard` drew **all seven charts** on canned data — sprint
burndown, velocity, cumulative flow, cycle time, work by state, pipeline pass
rate and the focus view — plus the layout, the four card states (skeleton,
Analytics refused, read failed, content) and the picker.
`dd05-probe`, `dd06-probe-1`, `dd06-probe-2`, `dd07-up-1`, `dd07-up-2`.

### 8. Chrome — pass

- **Search stays on Summary.** The magnifier is in the app bar on Summary and
  gone on Dashboards, where the picker is the title and the pill is rightmost.
  `dd11-home` against `dd12-dashboard`.
- **The Home pill is icon-only on the phone** and icon-and-label on the iPad
  (D13 icons: `summarize_outlined`, `dashboard_outlined`).
- **The dock is unchanged**: Home | Work | Repos | Pipelines, four
  destinations, `ProjectShell._destinations` untouched.
- **`_bleedsUnderRail` is untouched** — it still names only `/boards` and
  `/sprint`, so `/dashboards` keeps its inset and the page is clear of the
  glass rail in iPad landscape (checked on the device, item 2).

### 9. The D-C flags — all four found and fixed, plus the axis maximum

| D-C flag | Reproduced | Fixed by |
|---|---|---|
| the caption overlapping the top axis label | yes — `.shots/dc05-charts1_s.png` cropped shows `9.9` through the descenders of "items on the Stories today", and `1.1` through "average cycle time over 30 days" | fix 2 below |
| the final x label against the previous tick | yes — `14 Sep` next to `15 Sep`, and `15 Sep` clipped to `15 Se` at the card's edge | fix 4 below |
| plurals ("1 items") | **no** — already fixed by the end of D-C; the device reads "1 item" | fix 5 below |
| overflow at xxxL | **no** — nothing overflowed on either device at xxxL or AX XXXL, and the console is clean | — |
| *(asked as a question)* should the y axis top be a round number | yes, it was the headroom value on every chart | fix 2 below |

Everything that reproduced was fixed here, and the fixes were re-checked on the
device afterwards: `dd63-fix-cfd2` (cumulative flow `0 2 4 6 8`, `15 Sep`
whole), `dd64-label` (lead time `0 0.25 0.5 0.75`, velocity `0 1 2 3 4`),
`dd65-xxxl-charts` and `dd68-xxxl-cfd3` (xxxL, three gridlines), and the client
Burndown and Burnup drawing where they had read "Bad Request".

---

## What changed during the walk

### 1. The Burndown and Burnup widgets were a 400 on any real dashboard

Both cards on the populated client Overview read **"Bad Request"**. The widget
settings carry `aggregation: {identifier: 1, settings:
"Microsoft.VSTS.Scheduling.StoryPoints"}` — the work item **reference name** —
and `BurndownCard.load` passed that straight into the Analytics
`aggregate(… with sum as SP)`, which Analytics rejects: its entity calls the
same value `StoryPoints`.

`WidgetAggregation.analyticsField` now maps one to the other (System and
Microsoft fields drop their namespace, `Custom.Foo` becomes `Custom_Foo`,
anything already unqualified is passed through, so a settings value that is
already an Analytics name still works). Both cards now draw their series, and
the unit under the headline reads "points" instead of the whole reference name,
which was the same bug showing in the text. Tests in
`test/data/dashboard_models_test.dart`.

**This was invisible on the scratch project**: w36's Burndown widget stores no
aggregation, so it counted items and never hit the sum.

### 2. The y axis printed the headroom value, and it overlapped the caption

Every chart took `dataMax × 1.1` (or `× 1.15`) as the axis maximum and let
fl_chart choose the interval from that, so the axis named a number the data
could never take: nine items read **9.9**, seventeen read **18.7**, a bar of
two read **2.3**, and on the client velocity **81.1**. D-C had already tried to
drop the top label with `value >= meta.max`, but the generated values
accumulate rounding and the test failed by an epsilon often enough that the
label reappeared — and because it is centred on the plot area's top edge, half
of it landed in the card's caption ("9.9" through "items on the Stories today",
`.shots/dc05-charts1_s.png`).

`chartAxis` in `lib/theme/layout.dart` now rounds the maximum to a nice number
first (1 / 2 / 2.5 / 5 × a power of ten, at most `ticks` divisions), returns
the interval with it, and `ChartAxis.showsLabel` drops the top label against
**half an interval** rather than against the maximum, which no epsilon can
defeat. The four charts — cumulative flow, velocity, cycle/lead time and
`SprintBurndownChart` (shared with the Sprint page) — set `maxY`,
`horizontalInterval` and the label interval from it. Nine items now read
`0 2 4 6 8`; the client velocity reads `0 50 100`.

`integral: true` keeps the interval a whole number where the axis counts work
items, because "2.5 items" is not a quantity; the cycle-time scatter asks for
`strict: true` so a dot exactly on the maximum is not drawn half outside the
plot area.

### 3. The axis named numbers it was not drawing

With a quarter-day interval the shared one-decimal formatter printed the
gridline at 0.25 as **0.3** and the one at 0.75 as **0.8**. `ChartAxis.label`
now formats with exactly the precision the interval needs and trims trailing
zeros, so a fractional axis reads `0 0.25 0.5 0.75` and a whole-number one
still reads `0 2 4 6 8`.

### 4. The last x label was clipped, and the one before it crowded

`15 Sep` printed as `15 Se` against the card's edge: the final label is centred
on the plot area's right edge and the chart's 8 dp right padding is less than
half a `d MMM` label. `chartInsets` gives it `Spacing.sm + 14 × textScale`.

The "too close to the last tick, so skip it" rule was measured against
`meta.max`, which fl_chart reports for the **axis** and not for the point being
labelled, so `14 Sep` sometimes survived right next to `15 Sep`. All three
date axes now measure against the last index they actually hold.

### 5. "1 items" — already fixed, recorded

The plural in `.shots/dc05-charts1_s.png` was a mid-phase screenshot; `countOf`
had landed by the end of D-C and the device reads **"1 item"** on both the
Cycle Time and Lead Time cards (`dd15-ov-1`). Work by state likewise reads
"+1 more type". Nothing to do.

### 6. The tenth gridline label is deliberately absent

Worth saying out loud, because it looks like a bug: the topmost label is never
drawn. A 0–10 cumulative flow shows `0 2 4 6 8` and the band reaches the
unlabelled line above 8. Drawing it would need a line's worth of top padding on
every card, which the 220 dp chart cannot spare; the value is still one tick
above the highest label and the focus view, which has the room, is where the
exact numbers live anyway.

---

## Open items

- **Favorites-first ordering in the picker is unexercised on a device.** Nothing
  in puremedia is favorited and every project has one team with one dashboard.
  A favorite would have to be written, and only the scratch project may be
  written to — where it would still not prove an *ordering*, since there is one
  entry. Test-only until a tenant with several dashboards is available.
- **`project`-scoped dashboards have still never been seen**, here or anywhere
  (research/19 §1). Only `project_Team` is exercised.
- **The Analytics-refused notice (D14) is still test-only.** The host accepted
  every call in this run, so there was nothing to provoke.
- **The chart focus view opens from the card's title, not its plot area.** By
  design (fl_chart owns the touch inside the chart), but undiscoverable.
  Kelly's call whether a card needs an affordance.
- **`tool/shot-ios.sh` double-rotates landscape thumbnails on iOS 26.5**, where
  `simctl` already returns the rotated frame. Taps are unaffected.
- **Android is untested on this Mac**: its debug redirect URI is not on the app
  registration (research/09), so the app cannot sign in here.
- **Offline and a cold Analytics refusal** stay covered by widget tests.

## The Sprint page, which shares the chart

`SprintBurndownChart` is the Sprint page's chart as well as the dashboard's, so
the axis change was re-checked there: the Burndown tab on the iPad draws the
actual line, the dashed ideal, the weekend bands, the header sparkline and "The
numbers" exactly as P-D left them, with the y axis now reading `5 10 15` for a
sprint of 18 items instead of `9.9 19.8`. No regression. `dda3-sprint`.

## Gates

`flutter analyze` clean, `dart format` clean on every file this phase touched,
`flutter test` **1313 green** — 14 more than before the phase: the `chartAxis`
group in `test/theme/layout_test.dart` (ten: nice maxima, whole-number
intervals for counts, fractional for measurements, `strict`, a maximum already
on a step, degenerate input, the top label dropped against an epsilon, label
precision, tick thinning, the right inset) and the `analyticsField` group in
`test/data/dashboard_models_test.dart` (four). One existing assertion was
tightened: `dashboard_chart_cards_test.dart`'s velocity headline is now matched
on its text size, because a round y axis can label "8" as well.

The Dashboards feature's own test files run **191**.

## Scratch project afterwards

Unchanged. The Overview dashboard still holds the 13 widgets w36 wrote, the
saved query "Boardhop dashboard spike" is untouched, and no work item,
pipeline, favorite, vote or comment was written in this phase.
