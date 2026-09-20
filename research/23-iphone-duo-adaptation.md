# 23. iPhone Duo adaptation: the rail on the system's edge, the hinge as a layout line

Planned with Kelly on 2026-09-20, the day after Xcode 27.1 and the iPhone Duo simulator landed
on the Mac. `research/12b-iphone-duo-and-flutter.md` (2026-09-12) is the background: it predates
the SDK and the simulator and is corrected here where the two disagree. Decisions in section 3;
the build plan in section 5; state in NEXT-STEPS item 32. **Nothing in this document has been
built yet**: Kelly asked for the plan first.

## 1. What the SDK and the simulator show (verified 2026-09-20)

### 1.1 The device, from the simulator profile

`/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype` (device type
`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, model `iPhone19,4`, minimum runtime iOS
27.1, product family iPhone, idiom **phone**, scale 3, corner radius 59).

| Display | Pixels | Points | Native orientation | Notes |
|---|---|---|---|---|
| Inner (`primary-1`, screen id 3) | 2007 x 2853 | **669 x 951** | 270 (landscape-native) | `simctl io … screenshot --display=3` returns 2853 x 2007. All corners 55 px. |
| Outer (`primary`, screen id 1) | 1398 x 2034 | **466 x 678** | 0 (portrait) | Corners 8 px on the left edge, 59 px on the right: the hinge is the left edge of the cover. |

This confirms the 12b point sizes (they were inferred from a blog). The inner display is
`expanded` in the wide pose (951) and `medium` in the tall pose (669); the cover is `compact`;
a 50/50 Split View pane is about 475 x 669, `compact`. `Breakpoint` needs no change.

**Driving the fold from software (settled 2026-09-20).** There is no documented command:
`xcrun simctl` has no fold, hinge or posture verb (`simctl help`, `simctl ui`, `simctl io`
checked, and the `simctl`, CoreSimulator and SimulatorKit binaries carry no hinge strings);
`xcrun devicectl` sees the Duo simulator but CoreDevice's only hinge action is
`com.apple.coredevice.action.streamhingeangle`, a read stream served by the in-guest
`dtdeviceinfod`; there is no darwin notification, no defaults key and no CoreMotion file to write.
The pose buttons live in Device Hub's `CoreDevicePopDeviceKitExtension` plugin (`FoldableDevice`,
`HingeController`, `_transmitHinge`), which also carries an internal action bar
(`com.apple.dt.coredevicepop.useInternalV68ActionBar`: hinge slider, tabletop, more poses) that
was not tried. Xcode 27 replaced Simulator.app with **Device Hub** (bundle `com.apple.dt.Devices`,
process `DeviceHub`), which AppleScript's System Events cannot see at all (no menu bar, no
windows, unix id 0), but the **Accessibility API sees it directly**: `AXUIElementCreateApplication(pid)`
lists the window "iPhone Duo – iOS 27.1" with buttons whose `AXDescription` is **Rotate Right,
Closed, Book, Open** (plus Home, Screenshot, Record) and `AXPress` works on each. Verified with a
20-line Swift tool: Closed switched the active panel to the cover (screenshot of display 1
1398x2034, display 3 black), Book and Open switched it back to the inner display, Rotate Right
turned the inner screenshot to 2007x2853 and four presses returned it. That is the control path:
a press by accessibility name, no coordinates, no screen taps, and it survives window moves. It
needs Accessibility permission for the terminal (already granted on this Mac) and Device Hub
running with the Duo window open. Split View has no button; it is an in-guest gesture and is
driven with idb taps like any other UI, or by Kelly.

### 1.2 The app today on the Duo

A debug build with Xcode 27.1 (iOS 27.1 SDK) launches **edge to edge** on the inner display with
no code change: the page fills 951 x 669 and iOS stacks the status bar (time above the Wi-Fi
glyph) vertically in the top-right corner. That answers 12b appendix question 8: the rebuild
alone reaches tier 3. Kelly signed in during the planning session, so the shell was seen in three
poses:

- **Open, wide pose:** the glass rail floats on the right (Kelly's default) with its top level
  with the vertical status bar and clear of it by about 40 pt; the app bar keeps its actions.
- **Book (partly folded, wide pose):** the screenshot is identical to Open. The simulator does
  not paint a crease and the app has no crease input yet, so nothing moves; phase 0 measures
  whether the division region reports active here.
- **Closed (cover):** compact portrait, bottom glass bar, `medium`-style app bar collapsed to
  icons. The vertical status bar sits on the **right edge about 60 to 120 pt from the top**,
  over the page header's trailing side. The Dynamic Island shows no cutout in the simulator.

### 1.3 The iOS 27.1 APIs, exact spellings from the SDK headers

All in UIKit, all `API_AVAILABLE(ios(27.1))`, none present in Flutter's iOS engine (grep of
`engine/src/flutter/shell/platform/darwin/ios` for displayFeatures, hinge, reservedRegion,
verticalBar: nothing; only Android's `FlutterView` populates `MediaQuery.displayFeatures`).

- **Reserved regions** (`UIViewReservedRegion.h`, `UIView.h`): `-[UIView reservedRegionsOfKind:]`
  and `-[UIView reservedRegionsOfKind:options:]` (Swift: `reservedRegions(kind:)`,
  `NS_REFINED_FOR_SWIFT`). `UIViewReservedRegionKind.occlusionRegionKind` and
  `.divisionRegionKind`; each `UIViewReservedRegion` has `identifier`, `kind`, `frame` (in the
  view's coordinates, margins included), `margins` and `isActive`. Option
  `UIViewReservedRegionQueryOptionsIncludeInactive`. The selector `AppDelegate.swift` guesses today,
  `reservedRegionsOfKind:`, is **right**, but it passes an `NSNumber` where the API takes a
  `UIViewReservedRegionKind` object, so the selector path returns nothing useful and must become
  the typed call.
- **Vertical bar edge** (`UIVerticalBarEdge.h`): `UITraitCollection.verticalBarEdge` is
  `.unspecified`, `.leading` or `.trailing`; "reflects the system's preferred edge regardless of
  whether a vertical bar is currently visible" and is `.unspecified` on hardware or in a size
  class or orientation with no vertical bar. `UITraitCollection.systemTraitsAffectingVerticalBarEdge`
  is the array to pass to `registerForTraitChanges`.
- **Vertical bar behaviour** (`UIViewController.h`, `UINavigationItem.h`, `UIBarButtonItem.h`):
  `preferredVerticalBarBehavior` (`.automatic` / `.disabled`),
  `verticalBarCompressionBehavior` (`.automatic` prefers the tab bar, `.prefersBarItems`,
  `.prefersTabBar`), `UIBarButtonItem.axisBehavior` (`.horizontalOnly`, `.verticalPreferred`).
  These only affect UIKit-provided bars; Flutter draws its own, so they are not used.
- **Hinge** (`UIHinge.h`, `UIHingeInteraction.h`): `UIHinge.status` (`.unknown`, `.closed`,
  `.partiallyOpen`, `.fullyOpen`) and `angle`; `UIHingeInteraction(updateHandler:)` is a
  `UIInteraction` added to a view, `update.hinge` is nil on hardware without one.
- **Bar layout regions** (`UIViewLayoutRegion.h`): `layoutRegionForBarOnEdge:extent:` for
  positioning custom content relative to a bar edge. Optional.
- **Arrangements** (`UIArrangementViewController.h`, `UISplitArrangement.h`,
  `UIOverlayArrangement.h`): UIKit containers; not usable from Flutter.

Apple's HIG "Designing for iPhone Duo" (fetched 2026-09-20): "Controls on the side include both
system and app elements: the Dynamic Island, the status bar, the toolbar (including navigation
buttons), and the tab bar." "When two apps share the inner display with Split View multitasking,
each one places controls along its outer edge, so the left app has controls on the left." On the
cover display "the system places toolbars and tab bars on the side to maximize the vertical
space for content." "When the device is partially open, the folding region divides the inner
display into multiple usable regions, excluding the region at the center as the display folds."

### 1.4 What Boardhop has in place

- `lib/core/display_cutout.dart`: `DisplayCutout.regions()` returns `DisplayRegions` (typed
  `ReservedRegion`s, `hinge`, `folds`, `supported`, `cutoutSide`), tested through a mocked channel.
  `hinge` is computed and read by nobody; `ProjectShell` only calls `side()`.
- `ios/Runner/AppDelegate.swift`: channel `com.kammcs.boardhop/display` with
  `interfaceOrientation` and `reservedRegions` (selector path, see above). No push to Dart;
  Dart re-polls in `ProjectShell.didChangeMetrics`.
- `lib/features/projects/glass_shell_layout.dart`: the floating glass rail, right by default
  (Settings > Appearance switch), vertical in landscape, a bottom bar in portrait, positioned from
  `MediaQuery.padding` plus `CutoutSide`. No hinge or bar-edge input.
- Four hand-rolled master/detail screens (work items, wiki, code browser, PR files) split at a
  fraction of the width; `SideBySide` goes two-column from 880 pt of content width (Home, repo
  page, PR overview); dialogs and pickers center on the window from `medium` up.
- `Info.plist`: no `UIRequiresFullScreen`, `UIApplicationSupportsMultipleScenes` false.

### 1.5 Flutter's roadmap, checked 2026-09-20 (Kelly's question: does anything make this easier soon?)

- **Display features on iOS: yes, and soon-ish.** flutter/flutter#192515 (populate
  `MediaQuery.displayFeatures` on iOS for the Duo) is still open, P2, no maintainer comment, but
  it now has a linked engine PR, **#193025** by a community contributor (berkaycatak; created
  2026-09-18, marked ready for review 2026-09-19, no CI result yet, no team review yet). It adds a
  `FlutterDisplayFeaturesMonitor` that reads `UIHingeInteraction` and `reservedRegions` in
  `viewDidLayoutSubviews` and reports the fold as `DisplayFeatureType.fold` and the camera as
  `.cutout`. If it merges, the earliest stable is 3.48 (about November 2026) and more likely 3.49.
  It does **not** report the vertical bar edge or the hinge status, and it cannot say "this display
  folds but is flat right now" (Flutter's list model has no inactive feature), so
  `DisplayScope` keeps the channel for those three answers and takes `displayFeatures` for the
  rectangles once they arrive. The plan is built so that swap is one method.
- **Two windows of one Flutter app on iOS: no.** The multi-window umbrella (#142845) targets
  Windows and macOS only, its API is `@internal` behind a main-channel flag, and the iOS entry
  (#138168, "the iOS shell should support multiple views or windows") is an unscheduled
  "other platforms" pointer with no milestone. Nothing in the 3.47 notes or the umbrella mentions
  iPhone Duo or `UIApplicationSupportsMultipleScenes`. D4 stands: one window, two panes inside it.

## 2. Layout situations the app must handle

**Measured on the Duo simulator on 2026-09-20** (phase 0, §9); every number below came off
the device through the Display diagnostics page, not from guidance. `padding` and `viewPadding`
were identical in every row and `viewInsets` was zero throughout.

| Situation | Window (pt) | Breakpoint | padding l/t/r/b | Vertical bar edge | Division region | Hinge |
|---|---|---|---|---|---|---|
| Closed, portrait (cover) | **466 x 678** | compact | 0 / 0 / **84** / 34 | **trailing** | **none reported** | closed, 0.00 |
| Closed, landscape (cover) | **678 x 466** | medium | 0 / 0 / **84** / 34 | **trailing** | **none reported** | closed, 0.00 |
| Open, wide pose, flat | **951 x 669** | expanded | 0 / 0 / **84** / 34 | **trailing** | **inactive**, vertical, (455.5, 0) 40 x 669 | fullyOpen, 3.14 |
| Open, wide pose, partly folded (book) | **951 x 669** | expanded | 0 / 0 / **84** / 34 | **trailing** | **active**, **vertical**, (455.5, 0) 40 x 669, margins 20 left and right | partiallyOpen, 2.23 |
| Open, tall pose, flat | **669 x 951** | medium | 0 / **82** / 0 / 34 | **unspecified** | **inactive**, horizontal, (0, 455.5) 669 x 40 | fullyOpen, 3.14 |
| Open, tall pose, partly folded (book) | **669 x 951** | medium | 0 / **82** / 0 / 34 | **unspecified** | **active**, **horizontal**, (0, 455.5) 669 x 40, margins 20 top and bottom | partiallyOpen, 2.23 |
| Split View, left pane | not measured | — | — | — | — | — |
| Split View, right pane | not measured | — | — | — | — | — |

Three corrections to what this table used to predict:

- **The crease runs across the *short* axis, not the long one.** In the wide pose the division is
  a *vertical* band at the horizontal centre; in the tall pose it is *horizontal*. The fold line
  is always at the middle of the display's longer edge, whatever way up the device is held, and
  the earlier "horizontal band in the laptop pose" was wrong. The band is 40 pt wide with 20 pt of
  margin on each side, so **the crease itself is a zero-width line at the exact centre**
  (x = 475.5 in the wide pose, y = 475.5 in the tall pose) and the 40 pt is entirely the keep-out
  margin UIKit asks for around it.
- **The cover display reports a vertical bar edge too** (`trailing`), in both orientations, and
  reports **no division region at all** — so `folds` is false there and the pre-27.1 cutout answer
  still applies. D1 holds on the cover.
- **The tall pose reports `unspecified`**, as expected, so the bottom bar stays there.

The 84 pt right inset (82 pt top in the tall pose) is the stacked status bar, and it shows up in
`reservedRegions` as an **active occlusion** as well: (867, 0) 84 x 120 in the wide pose,
(382, 0) 84 x 170 on the cover in portrait, (535, 0) 134 x 82 in the tall pose. Flutter's
`MediaQuery.padding` already covers it, so the rail's clearance can come from `padding` and needs
no measured constant (§4.3). A second, **inactive** occlusion is reported where the camera sits on
the panel that is not in use (58 x 37 in the wide pose).

Split View could not be started from a script (§9, question 2); those two rows are still open.

## 3. Decisions (Kelly, 2026-09-20)

- **D1 Rail edge follows the system everywhere.** Wherever iOS reports a vertical bar edge
  (inner display, each Split View pane on its outer edge, the cover display) the glass rail sits
  vertically on that edge, whatever the orientation or breakpoint. A bottom bar only when the
  trait is `unspecified`, where today's rules stay (iPhone portrait, iPad portrait).
- **D2 Tab rail only, for now.** App-bar actions (view switch pill, New, search, overflow) stay
  in the horizontal app bar. Moving them into the side column, as Apple's vertical toolbar does,
  is a later step, recorded in section 7.
- **D3 Half open means two regions.** With an active division region, master/detail dividers
  and `SideBySide` gaps land on the crease, dialogs and pickers center on one half, the Kanban
  and sprint boards snap columns to the crease, and interactive content stays off the band.
- **D4 Split View scope is Boardhop beside another app.** One window resizing live to a 50/50
  pane on either side. Two Boardhop windows (`UIApplicationSupportsMultipleScenes`) stay out.
- **D5 First build covers all four layout groups:** master/detail panes, `SideBySide` and forms,
  Kanban and sprint boards, and the rich text editor under a live resize.
- **D6 The system edge wins over the Settings switch.** "Tab rail on the right" is hidden when
  iOS reports an edge and keeps working where it reports none (iPad and iPhone landscape).
- **D7 Layout changes animate** over the theme's standard duration: the rail slides between
  edges, panes ease to the crease. The hinge angle is not used for effects.
- **D8 Verification is live.** Kelly signed in on the Duo simulator; every check uses the
  puremedia scratch project "DevOps Mobile App". The demo build is only a fallback for the store
  screenshots.
- **D9 Poses are driven through the Accessibility API, not screen taps** (Kelly, 2026-09-20:
  find a software path before committing to taps; section 1.1 found one). A `tool/duo-pose`
  helper presses Device Hub's Closed, Book, Open and Rotate Right buttons by accessibility name.
  Split View is started in the guest with idb, or by Kelly if the gesture proves unreliable.

## 4. Design

### 4.1 Swift: one channel, typed calls, pushed changes

`AppDelegate.registerDisplayChannel` grows from two polled methods into a small display service
on the same channel name.

- `reservedRegions` becomes the typed call inside the existing `#available(iOS 27.1, *)` guard:
  `view.reservedRegions(kind: .division, options: .includeInactive)` and `.occlusion`, returning
  `[{kind, x, y, width, height, active, marginTop, marginLeft, marginBottom, marginRight}]` in the
  Flutter view's coordinates (points). Query the `FlutterViewController.view`; if it reports
  nothing while the window's root view does, fall back to the root view and convert. The
  selector code goes.
- `verticalBarEdge`: `view.traitCollection.verticalBarEdge` mapped to `"leading" | "trailing" |
  "unspecified"`, `"unspecified"` before 27.1.
- `hinge`: a `UIHingeInteraction` on the Flutter view, kept for its status only (`closed`,
  `partiallyOpen`, `fullyOpen`, `unknown`, `none` when `update.hinge` is nil).
- **Push:** the Runner calls `displayChanged` on the channel (Swift to Dart) from the hinge
  update handler, from `registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge + [UITraitHorizontalSizeClass.self])`,
  and from the Flutter view controller's `viewDidLayoutSubviews` (coalesced per frame), so a
  posture change that leaves the window size alone still reaches Dart.
- `interfaceOrientation` stays for iOS below 27.1 and non-folding hardware.

### 4.2 Dart: a `DisplayEnvironment` above the shell

`lib/core/display_environment.dart` (new) wraps the channel in a `ChangeNotifier` and an
inherited widget `DisplayScope` installed in `app.dart` above the router, next to `ThemeScope`.
It carries `DisplayRegions` (existing model, plus margins and an `axis` on each region),
`BarEdge {leading, trailing, unspecified}`, `HingeStatus`, and derived answers:

- `railEdge(TextDirection)`: leading or trailing resolved to left or right.
- `crease`: the active division region as a `Rect`, or null; `creaseAxis`: vertical (book) or
  horizontal (laptop, tent).
- `halves`: the two usable rects either side of an active crease, in window coordinates.
- `folds`: any division region exists, active or not (an inactive one still says "this display
  can fold", which is how a page decides to prefer an even number of columns).

`DisplayCutout` stays as the thin channel wrapper; `CutoutSide` keeps serving pre-27.1 devices.
`MediaQuery.displayFeatures` is consulted first if it is ever non-empty on iOS
(flutter/flutter#192515), so a future engine fix replaces the channel without a rewrite. Widget
tests drive `DisplayScope` with fixed values; nothing below the shell touches the channel.

### 4.3 The glass shell on the system's edge

`GlassShellLayout` gets `barEdge` and `crease` inputs from `DisplayScope` (via `ProjectShell`).

- `barEdge` specified: the vertical rail on that edge in every orientation and breakpoint,
  replacing `railOnRight`; the `RailSide` setting is ignored and its switch hidden (D6). The
  page gets the rail gutter on that side and a `SafeArea` on the others.
- `barEdge` unspecified: today's rules unchanged (bottom bar in portrait, rail per setting in
  landscape).
- **Vertical status bar.** iOS stacks the status bar in the corner on the rail's edge. Phase 0
  measures what `MediaQuery.padding` reports there; the rail then either starts below the
  reported top inset (if the inset covers the stacked status bar) or below a measured constant,
  and keeps the 80 % height rule inside what remains.
- **Compact panes.** A Split View pane is 475 pt wide; the rail gutter is 112 pt (24 margin +
  72 rail + 16), leaving 363 pt for content. The rail keeps its width and labels (the capsule
  behind icon and label is a settled rule) but the margin drops to `Spacing.md` when the window
  is compact, matching how close Apple's own vertical bar sits to the edge; measured in phase 2.
- **Crease.** The rail never spans an active horizontal crease: in the laptop pose it centers
  on the lower half (nearer the hands); in a book pose with a vertical crease the rail is on the
  outer edge already and nothing changes.
- Transitions: the rail's `Positioned` becomes `AnimatedPositioned` and the page's gutter
  `AnimatedPadding`, both on the theme's standard duration and curve (D7). Metrics changes
  already rebuild the shell; the pushed `displayChanged` triggers the same rebuild.

### 4.4 Hinge-aware layouts

A small helper set in `lib/theme/layout.dart` so every screen uses one vocabulary:

- `HingeGap`: for `SideBySide`, when a vertical crease is active and both columns fit, the
  column boundary and gap move to the crease (`Rect` from `DisplayScope`, converted to the
  builder's coordinates with `RenderBox.globalToLocal`); otherwise the flex split as today.
- `paneWidthFor(maxWidth, fraction, min, max, crease)`: the master/detail screens (work items,
  wiki, code browser, PR files) take the crease's left edge as the pane width when a vertical
  crease is active and it lies within `[min, max]`, otherwise the current fraction. The divider
  is drawn on the crease band, not next to it.
- `dialogAlignmentFor(context)`: `showDialog` and the picker helpers get an `alignment` and
  `constraints` that center the dialog on the half nearer the last touch (the near half is the
  one containing the tap that opened it, falling back to the trailing half); with a horizontal
  crease, the lower half. Applied through one wrapper (`showBoardhopDialog`) that the existing
  dialog-vs-sheet helpers call, so no page changes on its own.
- Kanban and sprint boards: the horizontal scroller gets snap points at column boundaries and
  the crease; a column never straddles an active vertical crease (the board's `padding` grows so
  the crease falls between columns). A horizontal crease (laptop pose) leaves the board alone;
  the drag proxy stays under the finger, which phase 3 verifies across the band.
- Work item form dialog: already `medium`-up dialog; centers on one half like the others. The
  form body's `wideMin` (640) means a half (about 475) stacks, which is the intended result.
- Off-the-band rule: `SafeArea`-like `CreasePadding` widget that pads a page's scroll content so
  no tap target sits inside an active crease band when the page spans it (single-column pages in
  the laptop pose). Used by the shell around every page; pages need nothing.

### 4.5 Rich text editor under live resize

`rich_text_control.dart` keeps the WebView in a stable slot. The test is: open a work item with a
description on the inner display, start Split View, fold and unfold, and rotate. Expected
failure modes: content lost, height wrong, editor recreated. Mitigations in order: size the slot
with a `LayoutBuilder` that only passes width changes to the editor through its own
`setWidth`/`reload`-free path; debounce width changes for the animation's duration; last resort,
snapshot the HTML before a resize and restore after recreation. The outcome is recorded in
research/spikes/results/README.md under a new F-number.

### 4.6 Tooling

- `tool/shot-ios.sh`: a `duo` device case (`DEVICE=duo` matches "iPhone Duo") and the `iphone`
  case made specific so an iPhone 17 beside a booted Duo is unambiguous; `DISPLAY=inner|outer`
  passes `--display=3|1` to `simctl io … screenshot`; the inner display's raw frame is
  landscape-native (2853 x 2007), so the thumbnail mapping treats it like `ROT=none` in the wide
  pose and derives the tall pose from the image reading taller than wide. idb `describe` on the
  Duo is checked in phase 0 for which display it reports and taps into.
- `tool/duo-pose.swift` (compiled once to `tool/.bin/duo-pose`, gitignored): `duo-pose closed |
  book | open | rotate [n] | list`. It finds the Device Hub process by bundle id
  `com.apple.dt.Devices`, takes its window whose title starts with "iPhone Duo", walks the
  accessibility tree for the `AXButton` with the wanted `AXDescription` and performs `AXPress`,
  then waits until `simctl io … screenshot` of the expected display stops being black (Closed
  activates display 1, Book and Open display 3). `list` prints the buttons it can see, which is
  the check to run when a Device Hub update renames them. Exit 2 when the window is missing, with
  the hint to open the Duo in Device Hub. Requires Accessibility permission for the terminal
  (System Settings > Privacy & Security > Accessibility; granted on this Mac).
- Screenshots follow the rotation on the Duo (after one Rotate Right the inner display
  captures 2007x2853), unlike the iPhone 17 whose raw frame stays portrait-native, so
  `shot-ios.sh` treats the Duo's `ROT` as none and reads orientation from the image.
- Split View is an in-guest gesture (app switcher, drag to a side); phase 0 records the idb tap
  sequence that starts it, and Kelly does it by hand if the sequence is flaky.
- CLAUDE.md gets a Duo paragraph under iOS simulators once phase 0 settles the commands.

### 4.7 Tests

- `test/core/display_environment_test.dart`: channel decoding, `halves`, `creaseAxis`,
  `railEdge` for both text directions, pre-27.1 fallbacks.
- `test/features/glass_shell_layout_test.dart`: rail on the leading and trailing edge in
  portrait and landscape, compact pane geometry, rail below a horizontal crease, setting ignored
  when the edge is specified.
- `test/theme/layout_test.dart`: `SideBySide` gap on a crease, `paneWidthFor` clamping, dialog
  alignment on either half.
- `test/features/work_items_page_test.dart` and the wiki, code browser and PR diff tests: pane
  width from a crease.
- Existing `display_cutout_test.dart` stays green.

## 5. Phases

Dispatcher mode: one Opus subagent per phase with the brief below; the top level reviews,
runs `flutter analyze` and `flutter test`, reads the diff and the screenshots, checks staged
files for secrets, and commits with the trailer. Subagents never commit.

**Phase 0, measure (half a day).** Land `tool/duo-pose` (4.6) first and the `duo` and `DISPLAY`
cases in `tool/shot-ios.sh`. A temporary diagnostics row (behind `AppConfig.diagnosticsEnabled`)
prints `MediaQuery.size`, `padding` per edge, `viewPadding`, `displayFeatures`, the raw channel
answers and `verticalBarEdge` for every row of section 2, driven pose by pose with `duo-pose`,
including both Split View sides. Output: section 2 filled with measured numbers, the 12b appendix
answered (questions 1, 3, 4, 5, 7, 8; question 2 by trying to drag the divider), screenshots to
Kelly. No layout changes.

**Phase 1, channel and model (one day).** 4.1 and 4.2: typed `reservedRegions`, `verticalBarEdge`,
`hinge`, `displayChanged` push, `DisplayEnvironment` and `DisplayScope`, tests. Verified by the
diagnostics row updating live while Kelly folds.

**Phase 2, the rail (one day).** 4.3: `GlassShellLayout` on the system edge, Settings switch
hidden, compact-pane margin, status-bar clearance, animation, tests. Verified: every row of
section 2, light and dark, both Split View sides, the rail never under the vertical status bar or
across a crease.

**Phase 3, hinge-aware layouts (two days).** 4.4 in this order: `SideBySide`, the four
master/detail screens, dialogs and pickers, `CreasePadding`, boards. Verified per screen in the
book and laptop poses with scratch data; drag across the crease on the Kanban board.

**Phase 4, the editor (half a day to a day).** 4.5, with the result written to the spikes README.

**Phase 5, documents (half a day).** DESIGN.md gains the hinge and bar-edge rules (and the stale
960 in section 6 becomes 880); research/12b gets a "verified 2026-09" addendum pointing here;
NEXT-STEPS item 32 records what landed; CLAUDE.md's Xcode paragraph and the simulator commands
are updated; a `research/walkthroughs/` report with the screenshots.

## 6. Acceptance

For each situation in section 2, on the scratch project, light and dark, default text size and
130 %:

1. Sign-in, project picker, Home, Work (list and detail), Boards, Sprint, Repos (browser and
   file), Pull requests (list, detail, diff), Pipelines, Wiki, Dashboards, Search, Settings.
2. Rail on the edge iOS reports; nothing under the vertical status bar; bottom bar only when the
   trait is unspecified.
3. Half open: dividers and gaps on the crease, no tap target inside the band, dialogs on one
   half, board columns snapping.
4. Split View on the left and on the right: rail on the outer edge, app bar actions collapse to
   icons, the editor keeps its content through the resize.
5. Transitions animate without a flash of the wrong layout; no layout asserts in the debug log.
6. `flutter analyze` clean, `flutter test` green, iPhone 17 and iPad Pro 13 unchanged
   (regression screenshots of Home in both orientations).

## 7. Out of this plan

- App-bar actions in the side column (D2): revisit after phase 3 with a mock-up.
- Two Boardhop windows (D4).
- Hinge-angle effects (D7).
- Store screenshots for the Duo: App Store Connect has not asked for a Duo size yet; add
  fixtures to `tool/demo-shots.sh` if it does.
- Android foldables: `MediaQuery.displayFeatures` is populated there, and `DisplayScope`'s
  fallback path picks it up, but nothing is verified on an Android foldable emulator.

## 8. Needs from Kelly

- Done 2026-09-20: signed in on the Duo simulator; the fold and rotate controls are driven by
  `duo-pose` (section 1.1), so nothing is needed from Kelly for the poses.
- Keep Device Hub open with the Duo window during walkthroughs (the accessibility path needs the
  window), and start Split View by hand if the idb gesture turns out flaky.
- Confirm the vertical rail on the cover display looks right once phase 2 has a screenshot; if it
  fights the vertical Dynamic Island, D1 narrows to the inner display and Split View.

## 9. Phase 0 findings (2026-09-20)

Measured on the booted iPhone Duo simulator (`58DEB6C0…`, iOS 27.1) with a **debug** build of the
real app, signed in, on the scratch project "DevOps Mobile App" (D8). What landed: `tool/duo-pose`
and its wrapper, the `duo` and `DISPLAY` cases in `tool/shot-ios.sh`, the typed Swift calls, the
Dart wrappers, and a **Display diagnostics page** at `/diagnostics/display` (the phone-link icon on
the Diagnostics page, `AppConfig.diagnosticsEnabled`). No layout changed.

### 9.1 Which view answers, and the trap that hid every answer

**`FlutterAppDelegate.window` is nil in this app.** Boardhop is scene-based
(`UIApplicationSceneManifest` in `Info.plist`), so the first typed implementation — which asked
`window?.rootViewController?.view`, exactly as the old selector code did — answered *nothing at all*
in every pose: no regions, `unspecified` for the bar edge, and a hinge that never got its
interaction installed. Going through the active `UIWindowScene`'s `keyWindow` instead fixed all
three at once. This is the single most important thing phase 1 must not undo.

With that in place, **the `FlutterViewController`'s own view answers every query** (`source` is
`flutterView` in all 24 regions measured, and the hinge interaction lives there too). The window
fallback was never needed. Regions come back in the Flutter view's coordinates, which are the
same as `MediaQuery`'s, so no conversion is needed.

### 9.2 The fold is invisible to Flutter

Folding from Open to Book and back **produced no `didChangeMetrics` at all** (the page's metrics
counter stayed at 1 across a full open → book → open cycle), and `MediaQuery.size`, `padding` and
`orientation` were byte-identical in the flat and folded rows. Only the channel sees the fold:
`hinge.status` goes `fullyOpen` (3.14 rad) → `partiallyOpen` (2.23 rad), and the division region's
`isActive` flips false → true. Its rect does not move.

So **the pushed `displayChanged` of §4.1 is not an optimisation, it is the only way a fold can
reach Dart**. Polling on `didChangeMetrics` (what `ProjectShell` does today) would never fire.
The `UIHingeInteraction` handler is lively — it ran 38 times during one fold — so it is a good
push source, and coalescing per frame matters.

`MediaQuery.displayFeatures` was **empty in every row**, as expected: nothing in Flutter's iOS
engine populates it yet (§1.5).

### 9.3 The appendix questions from research/12b

1. **Point sizes.** Inner 951 x 669 (`expanded`) in the wide pose, 669 x 951 (`medium`) in the
   tall pose; cover 466 x 678 (`compact`) portrait, 678 x 466 (`medium`) landscape; all at
   `devicePixelRatio` 3.0. The inferred sizes in 12b §3.1 were right. Split View not measured.
   **`Breakpoint` needs no change.**
2. **Split View divider.** *Not answered.* Split View could not be started from a script; see §9.4.
3. **Split View size class.** *Not answered*, same reason.
4. **`MediaQuery.padding` per pose.** Filled into §2. The shape is the same everywhere: **84 pt on
   the edge that carries the stacked status bar** (82 pt when it is the top edge in the tall pose),
   34 pt for the home indicator, 0 elsewhere — including 0 at the top of the *wide* pose, where the
   status bar is in the top-right corner rather than across the top. `viewPadding` equalled
   `padding` in every row and `viewInsets` was zero. `SafeArea` therefore handles the asymmetry on
   its own, and the rail's status-bar clearance can be taken from `padding` (§4.3) rather than a
   measured constant.
5. **Does `MediaQuery` update during a fold?** No — see §9.2. It does not update at all. There is
   nothing to animate from `MediaQuery`; the animation in D7 has to be driven by the channel.
6. **The editor under a live resize.** Phase 4; not touched.
7. **What the display channel returns on the inner display.** Everything, once the view lookup is
   right (§9.1): both region kinds with margins and `isActive`, the bar edge, and a live hinge.
   The old selector path returned an empty list, which Dart read as "asked, nothing in the way" —
   the "silently wrong rather than unknown" risk 12b called out was real, and is gone.
8. **Is a 27.1 rebuild enough for tier 3?** **Yes for the window, no for the crease.** A plain
   rebuild already fills both panels edge to edge, gets the right safe-area insets, and is handed
   the reserved regions when asked. What it does *not* get is any reaction to them: Flutter draws
   straight through the active division band, and nothing in the engine reports the fold. Tier 4
   is the work in phases 2 and 3.
9. **Long-press drag across the crease.** Phase 3; not touched.
10. **Flutter's response to #192515.** Answered in §1.5: still open, with a community engine PR
    (#193025) and no maintainer review.

### 9.4 Driving the Duo from a script (tooling findings)

- **`tool/duo-pose closed | book | open | rotate [n] | list`** works and is fast (about 1–2 s per
  pose). Two things the prototype did not hit:
  `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Devices")` returns
  a placeholder whose `processIdentifier` is **-1**, which no accessibility call can use, so the
  tool drops non-positive pids and falls back to the workspace list and then to `pgrep -x
  DeviceHub`; and the simulated screen is **in the same accessibility tree** under a group whose
  subrole is `iOSContentGroup`, so Boardhop's own buttons ("Search", "Wiki") would collide with the
  chrome — that subtree is skipped. `list` prints: Available, Search, Home, Screenshot, Record,
  Rotate Right, Closed, Book, Open, Hide Sidebar, Open in New Window.
- **Rotation.** One `Rotate Right` turns the wide pose into the tall pose; four return. Screenshots
  follow the rotation on this device (the inner panel captures 2853 x 2007 in the wide pose and
  2007 x 2853 in the tall one), so `shot-ios.sh` never rotates the Duo's thumbnail.
- **idb's HID taps only reach the cover panel.** `idb describe` reports the Duo as a single
  466 x 678 device (the cover), coordinate taps and swipes land there, and **a coordinate tap on
  the inner panel does nothing at all** — verified against several mappings and against a control
  tap that did launch the app from the cover's home screen. `idb ui button HOME` works on both.
- **idb's accessibility taps do reach the inner panel.** `idb ui tap --api ax <label>` matches
  against `AXLabel` and works on either panel, which is how every step of this walkthrough was
  driven; `shot-ios.sh` exposes it as `press "<label>"`. `idb ui describe-all` also works on the
  inner panel and returns frames in the *window's* coordinate space (951 x 669), which is a handy
  cross-check on a layout.
- **`xcrun simctl pbpaste <udid>`** reads the device pasteboard, so the diagnostics page's "copy as
  JSON" is the fastest way to get a whole pose off the device — no scrolling and no screenshot
  reading. That is how §2 was filled.
- **Mouse events into Device Hub's window do reach the inner panel**, including drags: a
  `CGEvent` left-drag over the rendered screen scrolled the page and opened the app switcher. The
  device screen sits inside the window at a scale that has to be found per window size (it was
  669 x 470 window points for a 951 x 669 display, so about 0.703, at window offset (379.5, 280.5)
  in a 1188 x 1023 window). This was a throwaway probe, not committed; if phase 3 needs a real
  long-press drag across the crease, this is the path to turn into a tool.

### 9.5 Split View: what was tried, and what is left for Kelly

Split View was **not started**, inside the 20 minutes allowed. What was tried, all on the inner
panel with the app open:

1. `idb ui swipe` and `idb ui tap` gestures — ruled out first: HID input does not reach the inner
   panel at all (§9.4).
2. A `CGEvent` swipe up from the bottom edge and hold, through Device Hub's window — **this worked**
   and opened the app switcher (Boardhop's card plus one other app).
3. From the switcher, a slow `CGEvent` drag of the Boardhop card to the left edge — no effect.
4. The same drag with a 1.4 s press before it moved (a long-press then drag) — no effect.

So the switcher is reachable and the card is not draggable by a single synthetic mouse pointer, at
least not the way it was shaped here; a real Split View start may need a different grab point (the
card's top handle), a second finger, or simply the trackpad. **Kelly:** start Split View by hand
once, leave the app in it, and the two pane rows of §2 can be filled with `tool/duo-pose` and the
diagnostics page in one pass (open the page, press *Copy as JSON*, then
`xcrun simctl pbpaste 58DEB6C0-6F8A-46A1-AAB5-217C2A2C5B20`). Device Hub has no Split View button
(`duo-pose list` confirms), so there is nothing to automate against yet.

### 9.6 Screenshots

`.shots/duo/` (gitignored), one pair per row: `<row>-diag-<inner|outer>.png` is the Display
diagnostics page and `<row>-home.png` is Home on the scratch project, each with a 400 px
`_s.png` thumbnail. Rows: `closed-portrait`, `closed-landscape`, `open-wide-flat`,
`open-wide-book`, `open-tall-flat`, `open-tall-book`. Only the active panel is captured: the other
one is solid black, which is also how `duo-pose` knows a pose has landed.

### 9.7 What phase 1 should change first

1. Keep the scene-based view lookup (§9.1) and keep `source` on each region — it is the only way to
   tell "nothing is reserved" from "the wrong view was asked".
2. Push, do not poll (§9.2): the hinge handler, `registerForTraitChanges` and
   `viewDidLayoutSubviews`, coalesced per frame.
3. `DisplayRegions.hinge` (the `Rect` getter) now has a `HingeState` beside it with the same name
   in a different shape. Phase 1's `crease` / `creaseAxis` should take over from the getter so one
   word does not mean two things.
4. The crease is a zero-width centre line with a 40 pt keep-out band around it (§2). `halves`
   should be computed from the *margins*, not from the frame, or each half will lose 20 pt it
   could have used.

### 9.8 Phase 1 landed (2026-09-20)

4.1 and 4.2 are built and verified on the Duo simulator with a **debug** build, signed in, on the
scratch project (D8). What landed: `displayState` and the pushed `displayChanged` in the Runner
(`ios/Runner/AppDelegate.swift`), `lib/core/display_environment.dart` with `DisplayEnvironment` and
`DisplayScope`, `DisplayRegions.hinge` renamed to `creaseBand` (with `activeDivision` beside it),
`ProjectShell` reading `DisplayScope.of(context).cutoutSide` instead of polling, the Display
diagnostics page reading the scope with a push counter and pull-to-refresh, and
`test/core/display_environment_test.dart`. **No layout changed** — that is phase 2.

**The fold reaches Dart, and nothing else does.** With the Display page open and the app untouched,
`tool/duo-pose book` raised the push counter from 0 to **17** (17 hinge updates, coalesced one per
runloop turn) while `metrics changes` stayed at **1**: `MediaQuery` still sees nothing, exactly as
§9.2 found. The page's division region flipped to active and the derived row filled in with
`crease 475.5, 0.0 0.0 x 669.0`, `creaseBand 455.5, 0.0 40.0 x 669.0`, `creaseAxis vertical`,
`halves 0.0,0.0 475.5 x 669.0 / 475.5,0.0 475.5 x 669.0` — the measured §2 numbers, on the device,
with no tap. `tool/duo-pose open` cleared all of them again (33 pushes by then). One
`duo-pose rotate` moved `verticalBarEdge` to **unspecified** and `railSide` to none, with the
division turning horizontal at `(0, 455.5) 669 x 40` and `padding` 82 pt on top — §2 row for row.
Screenshots: `.shots/duo/phase1-{open-wide,book,open,tall,tall-book,restored}.png` and the scrolled
`phase1-{derived,book-derived,open-derived}.png`, each with a 400 px thumbnail.

**The surprise: an unfold pushes a stale region.** The first build reported `hinge: fullyOpen`
beside `division: active` after opening from book, and stayed that way — UIKit flips a division
region's `isActive` **after** the hinge interaction has reported the new status, and on an unfold
nothing follows: no layout pass, no metrics change, no further hinge update. Phase 2 would have laid
out around a crease that was no longer there. The Runner now arms a single **settling re-read**
0.35 s after the last push of a burst (a `DispatchWorkItem`, cancelled and replaced by each push)
which sends only when a signature of the regions, the bar edge, the orientation and the hinge status
differs from what was last sent. With it, opening from book ends at 33 pushes with the division
inactive and `crease` null. A fold that changes nothing therefore still costs exactly zero extra
calls.

Three smaller findings:

- **The layout pass is observed, not subclassed.** The `FlutterViewController` comes from the
  storyboard by way of the implicit engine, so there is nothing to subclass from the app delegate.
  An inert zero-alpha `DisplayLayoutObserver` sits behind the root view, sized to the window by its
  autoresizing mask, and its `layoutSubviews` runs in the same pass. It takes no touches
  (`hitTest` returns nil) and is not an accessibility element, and `idb ui tap --api ax` kept
  working on the inner panel throughout, which is the check that it stays invisible to the tree.
- **Installed at registration, not on first use.** The observers (hinge interaction, trait
  registration, layout observer) go in as soon as the scene is up — retried every 0.25 s until it
  is, with `applicationDidBecomeActive` as the backstop — so a fold before anything asks is not
  missed. Pushes are held until Dart has called `displayState` once, so they cannot race startup.
- **`registerForTraitChanges` needs the typed array.** `UITraitCollection
  .systemTraitsAffectingVerticalBarEdge` is `NS_REFINED_FOR_SWIFT` and arrives in Swift as
  `[any UITraitDefinition.Type]`; the two size classes are appended to it.

Left for later: Split View is still unmeasured (§9.5 — Kelly starts it by hand), so the two pane
rows of §2 and the `compactPane` behaviour are covered by unit tests at 475 x 669 and not yet by the
device. `halves` is computed from the margins, as §9.7 asked, so the two halves meet on the crease
line and neither loses the 20 pt keep-out; keeping content out of the band is `CreasePadding`'s job
in phase 3.
