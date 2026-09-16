# Launch and project switching — iOS walkthrough, 2026-09-15

Acceptance of research/21 (§5) on Apple hardware, after the feature was built
and accepted on the Android emulators the same day (research/21 §6). Devices:
iPhone 17 simulator `9CB22607-F6D0-4C47-8B2D-4AC4F60A6A31` and iPad Pro
13-inch (M4) `929DE352-434C-4CE6-BB96-5C34212741E8`, **debug** builds from
`flutter run --dart-define-from-file=.env` (consoles `iphone.log`,
`iphone2.log`, `ipad.log` and `ipad-attach.log` in the session scratchpad).
Signed in as Kelly (puremedia). iOS matters here because the project shell's
chrome on Apple platforms is the glass shell (`GlassShellLayout`), not
Material's `NavigationBar`: the picker sheet and the anchored panel share the
screen with a floating dock (portrait) or rail (landscape) rather than a solid
column, so their clearance had to be seen rather than assumed.

**No Azure DevOps writes of any kind.** Everything was read; the two theme
radios and the "Tab rail on the right" toggle are device-local settings and
were put back. The scratch project **DevOps Mobile App** was opened as the
first act on both devices and is what every screenshot below shows. Client
projects were passed through only to exercise the picker's switch (CloudCover
2.0 was the remembered project at first launch, and one mis-aimed tap landed
on Product's Home); **no client screenshot is named in this document and none
is to be sent on.** Screenshots live in `.shots/` (gitignored), `li*` for the
iPhone and `lp*` for the iPad.

**Console: no `EXCEPTION`, no `overflowed`, no `RenderFlex`, no failed
assertion** on either device. The coverage is partial by construction and is
stated honestly below.

**No code was changed.** Nothing on either device behaved incorrectly, so
there was nothing to fix; three observations are left for Kelly at the end.

---

## Console coverage, stated plainly

A cold start here means `xcrun simctl terminate` + `xcrun simctl launch`, and
terminating the app drops `flutter run`'s connection to it. So the run splits
into attached stretches and detached ones:

| Device | Attached (console watched) | Detached |
|---|---|---|
| iPhone | the whole regression walk — four tabs, the picker on each, Dashboards, Wiki, Search, a work item, a PR, Board, Sprint, both themes, xxxL | the three cold starts and the missing-project fallback |
| iPad | first launch through the four tabs and both orientations; then a fresh `flutter attach` for a closing sweep (four tabs, the picker twice, a project switch) | the cold start and the stretch between |

Every attached stretch was clean. The detached stretches were judged from the
screenshots alone, which is enough for layout and navigation and not enough
for a silent assert; the closing attached sweep re-walked the same screens
to cover that gap.

---

## research/21 §5, item by item

| # | Item | iPhone 17 | iPad Pro 13" |
|---|---|---|---|
| 1 | Cold start to the remembered project's Home | **pass** | **pass** |
| 2 | First sign-in on a fresh install → first alphabetical project | **not demonstrable** | **not demonstrable** |
| 3 | Tile ▾ on all four tabs; rows switch; current ticked; sheet drags full / panel anchors | **pass** | **pass** |
| 4 | Sign out with a second account; Add account | **not demonstrable** | **not demonstrable** |
| 5 | Bell dot appears and clears | **pass** | **pass** (no unread to clear) |
| 6 | `/orgs` and the project list still open | **pass** | **pass** |
| 7 | Remembered project gone → fallback with the snackbar | **pass** | **not re-run** (proved on the iPhone) |

### 1. Cold start straight to the remembered project — pass on both

**iPhone.** The first `flutter run` launch came up on the project the device
already remembered from an earlier session, with no Organizations page and no
project list in between (`li01-launch`). Switching to **DevOps Mobile App**
through the picker (`li04-switched`), then `simctl terminate` + `simctl
launch`, landed on DevOps Mobile App's Home (`li05-coldstart`). A second,
harder case: the app was left on the **Accounts** page (`/orgs`, not a project
route) and killed there; the next launch still opened DevOps Mobile App
(`li15-relaunch`), which is `ProjectMemory` correctly ignoring the
organization-level routes.

**iPad.** First launch opened the iPad's own remembered project
(`lp01-launch`, `lp02-dismiss`); after switching to DevOps Mobile App
(`lp04-switched`), terminate and launch landed there (`lp25-coldstart`).

One thing worth recording about the iPad's first launch: an MSAL
`login.microsoftonline.com` password sheet appeared over the Home page a
second after it painted (`lp01-launch`) — a silent token refresh that needed
interaction. Dismissing it left the app working and fetching live data for the
rest of the run (fresh pipeline runs in `lp07-pipes-panel`), so it was a
one-off refresh, not a feature defect. It is noted because a store reviewer
could meet the same sheet.

### 2. First sign-in on a fresh install — not demonstrable

Same reason as Android: the simulators are already signed in, and proving this
would mean wiping the account and signing in again with Kelly's credentials.
The resolver's `preferAccountId` path is unit-tested.

### 3. The tile ▾, the sheet and the panel — pass on both

**iPhone (bottom sheet, L2).** The picker opened from **Home**
(`li02-picker`), **Work** (`li07-work-picker`), **Repos**
(`li08-repos-picker`) and **Pipelines** (`li09-pipelines-picker`). It opens at
0.6 showing the account header (avatar, address, tenant, sign-out), the
`puremedia` row with its chevron and the four projects with the current one
ticked; dragging it up reaches 0.95 and reveals **Add account**, **Manage
accounts**, **Activity** (with its own dot and "2 new"), **Settings** and
**Diagnostics** (`li03-picker-full`). The last row clears the floating dock —
the content's `SafeArea(top: false)` is spending the shell's bar gutter, so
Diagnostics is tappable rather than hidden under the glass.

Tapping **DevOps Mobile App** switched project and rebuilt the page: header
*and* body both belong to the new project (`li04-switched`), so the
router's per-project `ValueKey` fix from the Android run holds on iOS too.

**iPad (anchored panel, L2).** The panel anchors under the tile, 360 pt wide,
shrink-wrapped to its content, from **Home** (`lp03-panel`), **Work**
(`lp05-work-panel`), **Repos** (`lp06-repos-panel`) and **Pipelines**
(`lp07-pipes-panel`). In portrait it ends far above the dock
(`lp21-dark-portrait`).

**The landscape case, which is the one the glass shell could have broken.**
With the rail on the right (Kelly's setting) the panel hangs off the tile at
the top left and never comes near it (`lp14-land-panel`). With **Tab rail on
the left** — flipped in Settings for this check and put back — the app bar's
tile has already moved right of the rail gutter, so the panel starts right of
the rail and clears it as well (`lp20-leftrail-panel`, dark). In neither
orientation is there a dock in landscape to collide with. The panel's 70 %
height cap leaves it ending around three-quarters down the screen.

### 5. The Activity bell — pass

On the iPhone the bell carried a dot at launch (`li01-launch`) and the picker
agreed with it ("Activity · 2 new", `li03-picker-full`). Opening Activity from
the bell showed the feed with two dotted items (`li11-activity`); coming back,
the bell was plain (`li12b-bell-cleared`) and stayed plain across the next
cold start. On the iPad the bell is in the same place on all four tabs and
opens the feed (`lp15-bell`); there was nothing unread left to clear by then,
so the clearing half is the iPhone's evidence.

### 6. `/orgs` and the project list — pass on both

**Manage accounts** opens the Organizations page, and its app-bar title now
reads **Accounts** (`li13-accounts`, `lp26-accounts`). Its `puremedia` row
still opens the project list (`lp27-projectlist`), and a project row from
there still enters the shell (`lp28-dash` followed from it). Both are `go`
rather than `push`, so there is no back arrow out of Accounts — the route is
deliberately out of the main flow (L3), and the way back is the org row.

`li14-projectlist` caught a transient "No connection. Check your network and
try again." on the Accounts page. It was a real refresh failure at that
moment, not a launch-feature fault: everything before and after it fetched
normally.

### 7. The fallback and its snackbar — pass on the iPhone

The device memory was edited by hand — `/usr/libexec/PlistBuddy -c 'Set
:flutter\.launch\.last\.project "Gone Project"'` on the app's
`com.kammcs.boardhop.plist` with the app terminated. (`defaults write` from
the host is *not* enough: the simulator's `cfprefsd` serves its cached copy
back and the edit is lost, which is what the first two attempts showed.)

On the next launch (`li34-fallback`) the shell opened "Gone Project" without
pre-checking it (L8 as designed), every Home section showed the service's
`TF200016: The following project does not exist` line, and the snackbar
**"Gone Project" is not available any more · Choose another project** was up
with the first frame. Tapping the action within its 8 s opens the picker
(`li36-choose`), correctly with no row ticked. Switching from there put the
scratch project back.

---

## Regression checks — the recent Mac features under the new app bars

All on the iPhone unless noted; all **pass**.

| Check | Evidence |
|---|---|
| Home pill Summary / Dashboards / Wiki still fits beside the tile, bell and magnifier | `li01-launch` (three segments, icons only at compact width) |
| A dashboard opens and renders | `li16-dashboards`; iPad grid `lp28-dash` |
| A wiki opens, tree and page | `li17-wiki`, `li18-wikipage`; iPad two-pane `lp29-wiki` |
| Search from Home | `li19-search`; iPad `lp31-search` |
| Work pill Items / Board / Sprint | `li24-board`, `li25-sprint`; iPad `lp32-board`, `lp33-sprint` |
| A work item opens and goes back | `li20-workitem` → `li21-home-back`; iPad `lp36-item` |
| A PR opens and goes back | `li23-prpage` (PR !8334) |
| Settings opens from the picker | `li42-settings`, `lp18-settings` |
| Both themes | iPhone `li26-dark-work`, `li43-dark-home`, `li44-dark-work`; iPad `lp19-dark-set`, `lp20-leftrail-panel` |
| xxxL dynamic type | iPhone `li30-xxxl-home`, `li31-xxxl-picker`; iPad `lp22-xxxl` |
| iPad both orientations | portrait `lp04-switched`, landscape `lp13-test`, `lp14-land-panel` |

The back arrow is replaced by the tile on the four **root** tabs only, exactly
as designed: Dashboards, Wiki, Board, Sprint, the work item and the PR all
keep their back arrows (`li16`, `li17`, `li24`, `li25`, `li20`, `li23`).

At xxxL nothing overflows. The Home app bar still carries tile ▾, a
one-character title, magnifier, bell and the three-segment pill
(`li30-xxxl-home`), and the picker's rows grow without clipping — the account
address ellipsises (`lp22-xxxl`).

A note on the tooling, for the next agent: on this Mac `xcrun simctl io …
screenshot` returns an **already-rotated** landscape frame for the iPad, while
`idb ui tap` still wants the portrait frame. `tool/shot-ios.sh`'s `ROT=` mode
maps taps correctly but then rotates the thumbnail a second time, so the
picture comes out sideways. The landscape shots here were taken with a small
wrapper that keeps `ROT=left`'s tap mapping and leaves the thumbnail alone.
Worth folding into `shot-ios.sh` if iPad landscape work continues.

A second tooling note: an app launched by `simctl launch` (detached from
`flutter run`) does not pick up `xcrun simctl ui … appearance dark` — the
trait change never reaches it. The dark-theme shots here were taken by
choosing **Dark** in the app's own Settings instead, which is the more
faithful check anyway; Appearance was put back to **Match system** on the
iPhone and **Light** on the iPad, as each was found.

---

## Fixes

**None.** No assert, no overflow, no broken tap, nothing mis-rendered. The two
defects the Android run found (the stale page body after a switch, the double
drag handle) were already fixed there and are correct here.

---

## Open items for Kelly

1. **The compact-width titles — Kelly's own question, now photographed.** On
   the iPhone the Home title is `De…` (`li43-dark-home` dark,
   `li15-relaunch` light) and the Work title is `De…` over `As…`
   (`li44-dark-work` dark, `li06-work` light) — three characters and an
   ellipsis, worse than Android's `DevO…` because the pill segments are wider
   here. It is the tile ▾ plus the bell plus a three-segment pill that spends
   the width; Repos and Pipelines, which have one action each, show the full
   "DevOps Mobile App" and its subtitle (`li08-repos-picker`,
   `li09-pipelines-picker`), and the iPad shows it everywhere. The project
   header immediately below the Home app bar already names the project in
   full. **The layout was not changed** — this is Kelly's call. Dropping the
   Home title at compact width, as research/21 §6 suggested, would cost
   nothing on Home; Work's second line ("Assigned to me") is the only piece
   of information not repeated elsewhere on that page.
2. **The fallback snackbar overlaps the floating dock** (`li34-fallback`): it
   is laid out against the shell's Scaffold, which on Apple platforms has no
   `bottomNavigationBar` for the snackbar to sit above, so it covers the top
   of the glass dock for its 8 s. Transient and readable, and the action is
   reachable, so it was left alone — but it is the kind of thing Kelly
   notices, and every snackbar raised from the shell shares it.
3. **The picker's own modal parent differs by entry point.** Opened from the
   tile, the sheet is pushed on the branch navigator and the glass dock floats
   over its bottom edge (`li02-picker` — harmless, the content clears it).
   Opened from the fallback snackbar's "Choose another project", it covers the
   dock entirely (`li36-choose`). Cosmetic, one line to make consistent if
   Kelly wants it, but it is a design choice rather than a defect.

## Gates

`flutter analyze` clean, `flutter test` green (1615 tests), `dart format`
applied to the files touched (documentation only).
