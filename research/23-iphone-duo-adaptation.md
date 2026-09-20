# 23. iPhone Duo adaptation: the rail on the system's edge, the hinge as a layout line

Planned with Kelly on 2026-09-20, the day after Xcode 27.1 and the iPhone Duo simulator landed
on the Mac. `research/12b-iphone-duo-and-flutter.md` (2026-09-12) is the background: it predates
the SDK and the simulator and is corrected here where the two disagree (its own addendum points
back). Decisions in section 3; the build plan in section 5; state in NEXT-STEPS item 32.

**Built and verified on the simulator the same day**, in six commits — `f1137de` phase 0
(measurement and tooling), `4c07c65` phase 1 (the channel and `DisplayScope`), `c61300c` phase 2
(the rail on the system's edge), `f7275a5` phase 3 (the crease as a layout line), `608dc47`
phase 4 (corner clearance, the editor under a live resize), `0654052` phase 4b (the chrome above
the router, dialogs that follow a fold), and phase 5 for the documents and the two fixes those
phases left. What each one found and landed is section 9; the walkthrough report is
`research/walkthroughs/2026-09-20-iphone-duo.md`. Nothing has been seen on hardware, and Split
View has never been entered (section 8).

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
| Split View, left pane (Kelly started it by hand, 2026-09-20, Safari on the right) | 469 x 669 | compact | 0 / 0 / 8.7 / 34 | **leading** | inactive, vertical, clipped to the pane at x 455.5 (13.5 pt of the 40 pt band visible), margins 20 | fullyOpen 3.14 |
| Split View, right pane (Kelly swapped the sides) | 469 x 669 | compact | 8.7 / 0 / **84** / 34 | **trailing** | inactive, vertical, clipped to the pane at x 0 to 13.5, margins 20 | fullyOpen 3.14 |

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
- **D10 Bare rail inside the system's column** (Kelly, 2026-09-20, after the first phase 2 build):
  on an edge iOS names, the glass pill goes: "it makes it too wide and the icons are not aligning
  properly under the combo status icon like it does on the Apple-made apps". The destinations sit
  bare inside the 84 pt column iOS reserves, centred on the status cluster's x, stacked with
  `Spacing.lg` and centred below the cluster; only the selected capsule keeps its glass. The pill
  stays wherever the edge is unspecified. Content width: 867 pt inner, 382 pt cover.
- **D11 A sharp fade before the column** (Kelly, same day): content under the column read as
  clutter on the Boards card wall, so every page under a system edge fades to transparent on a
  `Spacing.md` cliff ending at the column's inner boundary (`ShaderMask`, `dstIn`); bleeding
  pages still scroll under it so the last column reaches the visible area.
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

**Phase 0, measure — landed (`f1137de`).** Land `tool/duo-pose` (4.6) first and the `duo` and
`DISPLAY` cases in `tool/shot-ios.sh`. A temporary diagnostics row (behind `AppConfig.diagnosticsEnabled`)
prints `MediaQuery.size`, `padding` per edge, `viewPadding`, `displayFeatures`, the raw channel
answers and `verticalBarEdge` for every row of section 2, driven pose by pose with `duo-pose`,
including both Split View sides. Output: section 2 filled with measured numbers, the 12b appendix
answered (questions 1, 3, 4, 5, 7, 8; question 2 by trying to drag the divider), screenshots to
Kelly. No layout changes. Findings in §9.1 to §9.7.

**Phase 1, channel and model — landed (`4c07c65`, §9.8).** 4.1 and 4.2: typed
`reservedRegions`, `verticalBarEdge`, `hinge`, `displayChanged` push, `DisplayEnvironment` and
`DisplayScope`, tests. Verified by the diagnostics row updating live while Kelly folds.

**Phase 2, the rail — landed (`c61300c`, §9.9).** 4.3: `GlassShellLayout` on the system edge,
Settings switch hidden, compact-pane margin, status-bar clearance, animation, tests. Verified:
every row of section 2, light and dark, the rail never under the vertical status bar or across a
crease — but **not** the two Split View sides, which could not be entered (§9.5).

**Phase 3, hinge-aware layouts — landed (`f7275a5`, §9.10).** 4.4 in this order: `SideBySide`,
the four master/detail screens, dialogs and pickers, `CreasePadding`, boards. Verified per screen
in the book and laptop poses with scratch data; drag across the crease on the Kanban board.

**Phase 4, corner clearance and the editor — landed (`608dc47`, §9.11 and §9.12).** 4.5, with
the result written to the spikes README as F6 — and, unplanned, the corner-adapted clearance
Kelly asked for when she saw the picker's icon in the curve. The three things it left open closed
as **phase 4b** (`0654052`, §9.13): `WindowChrome` above the router, dialogs that follow a fold,
and the rich text editor's own dialog.

**Phase 5, documents — landed.** DESIGN.md gained the fold and bar-edge rules in sections 6 and
7, the Duo poses in the section 9 checklist, and 880 in place of the stale 960; research/12b
gained a "Verified 2026-09-20" addendum pointing here; CLAUDE.md gained an iPhone Duo bullet with
the commands; the walkthrough report is `research/walkthroughs/2026-09-20-iphone-duo.md`;
NEXT-STEPS item 32 records what landed. Two fixes left by phase 4b landed with it: the standalone
`WorkItemDetailPage` takes the `SafeArea(top: false, bottom: false)` convention (the embedded pane
is untouched), and the Diagnostics index folds its probes into an overflow menu on a compact
width. Verified on the cover and in the wide and tall poses,
`.shots/duo/phase5-{cover-wi,cover-diag,cover-diag-menu,wide-diag,tall-book-diag,wi-open}`; the
comments now end at 382 on the cover, where the column starts, and a full circuit logs no
exception. 1957 tests green.

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

Done on 2026-09-20 and no longer needed: the sign-in, the poses (`duo-pose` drives them), and
the cover rail, which Kelly reviewed mid-phase-2 and turned into D10 and D11. What is left:

- **Start Split View by hand, once.** It cannot be started from a script (§9.5) and Device Hub has
  no button for it. With the app left in a pane, the two pane rows of section 2, a pane's size
  class and the corner insets of its inner edge fill in one pass — open `/diagnostics/display`,
  press *Copy as JSON*, then
  `xcrun simctl pbpaste 58DEB6C0-6F8A-46A1-AAB5-217C2A2C5B20`.
- **A physical device**, when it ships on 2026-10-23, for the two things a simulator cannot
  answer: the board's snap after a real fling (synthetic mouse drags do not scroll on iOS, §9.10)
  and how a long-press drag across the crease *feels* over a real fold.
- Keep Device Hub open with the Duo showing during a walkthrough; the accessibility path needs the
  window.
- **Optional, a decision rather than a need:** in the tall pose iOS reports no vertical bar edge,
  so no corner clearance is applied and a back arrow sits at x = 4 beside a 16 pt corner (§9.13).
  Widening the rule to every pose that reports a corner would move that arrow and nothing else.

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
6. **The editor under a live resize.** **Nothing breaks.** Folding, unfolding, rotating and
   folding again with the `html_editor_enhanced` WebView live left the content intact, the
   WebView un-recreated (one `onInit`, no dispose) and the log clean; `getText()` still
   answered afterwards. The one imperfection is the slot's **height**, which is frozen at
   the value of the first build and is not worth unfreezing. Measured in §9.12, recorded as
   F6 in `research/spikes/results/README.md`.
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

### 9.9 Phase 2 landed (2026-09-20)

4.3 is built and verified on the Duo simulator with a **debug** build, signed in, on the scratch
project (D8). What landed: `GlassShellLayout` rebuilt around one plan (a rail box and a page) with
the system's bar edge as its first input, `GlassNavigationRail` given a **`chrome`** of
`pill` or `bare`, `ProjectShell` passing `railSide`, `occlusions`, `creaseBand` and `creaseAxis`
from `DisplayScope`, `DisplayEnvironment.occlusions`, the Settings switch hidden where iOS names
the edge, `Motion.standard` (`Curves.easeInOutCubic`) beside `Durations` in `lib/theme/tokens.dart`,
and twelve new widget tests (ten in `test/features/glass_shell_layout_test.dart`, which is
nineteen now, and `test/features/settings_rail_switch_test.dart`).

**The rail is inside the system's column, not beside it (Kelly, mid-phase).** The first build put
the glass pill on the system edge with its 24 pt margin, and Kelly rejected it from the screenshots:
the pill is too wide for the column iOS reserves and its icons do not line up under the stacked
status cluster the way Apple's own vertical tab bar does. The rule is now:

- The rail sits **in** the reserved column — the 84 pt `MediaQuery.padding` already reports on that
  edge — and the page keeps **no gutter beyond that inset**. Measured on the device:
  **867 pt of content on the inner display** (951 - 84) and **382 on the cover** (466 - 84); the
  glass pill left 839 and 366.
- `GlassRailChrome.bare` drops the container: no `BackdropFilter`, no tint, no hairline, no shadow.
  Bare destinations, icon over label, stacked with `Spacing.lg` between them and centered in what
  is left below the cluster. The **selected destination keeps its capsule** of brighter glass
  behind icon and label; nothing is signalled by color.
- The column is centered on the **status cluster's own x** (the active occlusion's centre) and
  starts below it. `idb ui describe-all` on the inner display reads back
  `x 873 w 72` for all four destinations — centre **909**, exactly the cluster's centre and the
  reserved column's — at `y 253.5 / 319.5 / 385.5 / 451.5`, a 66 pt pitch (50 pt item + 16 pt gap),
  so the column runs 253.5 to 501.5 and is centered in the 120 to 635 strip below the cluster.
  The 80 % height rule is the pill's and does not apply here.
- The pill is untouched everywhere the edge is unspecified: the bottom bar in portrait, the rail in
  landscape on an iPad or an iPhone, the Settings switch, `bleedsUnderRail`, `_keyboardSafe`.

**And the page fades out at the column (Kelly, same day, after the Boards shots).** With no glass
behind the glyphs, content passing under them read as clutter — badly on the cover, where a Kanban
column is wide enough to run under the rail at rest. Every page under a system edge is now wrapped
in a `ShaderMask` (`BlendMode.dstIn`, `GlassShellLayout.columnFade`): whole across the page, a
cliff `Spacing.md` wide, nothing from the column's inner boundary on — 867 pt on the inner display,
382 on the cover, the same number the page's gutter uses, so the cliff sits exactly where the
column starts. The mask wraps the page body only, so the Scaffold's overlays (a floating snackbar,
a sheet) are untouched, and a `ShaderMask` takes no taps, so a sideways scroller still scrolls
under the column: verified on the cover that the board's **last column comes fully into the visible
area** at the end of its scroll (`.shots/duo/phase2-closed-board-scrolled.png`), because the column
is its end padding. Before and after: `.shots/duo/kelly-boards-{closed-portrait,open-wide}-post.png`
and the same names with `-fade`. The app bar's own trailing pill ends at 855 on the inner display,
12 pt clear of the cliff, so nothing of it is lost.

**Verified, light and dark** (`.shots/duo/phase2-*`, each with a 400 px thumbnail): closed portrait
and closed landscape on the cover, open wide flat, open wide book, open tall flat, open tall book,
plus Work (master/detail) and the Kanban board in the wide pose. The bar edge is `trailing` in
every pose but the tall one, where it is `unspecified` and the glass bar stays along the bottom, in
the lower half already. Regression: iPhone 17 portrait and landscape and iPad Pro 13" portrait
(`phase2-regress-*`) are unchanged, and their debug logs are clean.

Three findings:

- **A window about 140 pt tall exists.** The debug log caught `A RenderFlex overflowed by 77 pixels`
  from the vertical rail at startup: for a frame the Duo reports a landscape window far shorter than
  the rail's own 216 pt, and four fifths of that is less than its destinations need. It is not new
  — the same maths applied before phase 2 — but it is now fixed: `GlassNavigationRail.lengthFor`
  gives the shell the rail's own length and the box is never shorter, overhanging the window
  instead of squeezing. A full pose circuit (wide, book, tall book, tall, cover, back) now logs
  **no exception at all**.
- **The board's bleed is harder to read under a bare rail.** A sideways scroller still gets the
  column as `MediaQuery` padding and slides under it, but with no glass behind the glyphs the
  labels sit straight on the cards. It reads well enough on the inner display and badly on the
  **cover**, where a column of the Kanban board is wide enough to run under the rail at rest
  (`.shots/duo/kelly-boards-closed-portrait-post.png`). Kelly's answer was the fade above rather
  than stopping the bleed, so a horizontal scroll still reaches the last column.
- **Animation is by box, not by content.** The rail's `AnimatedPositioned` would hand a
  four-item bar every width between the bottom bar and a 72 pt column, so the rail is laid out at
  the size it is **heading for** (`_RailSlot`, an `OverflowBox`) and glides. The page's gutter is
  an `AnimatedPadding` on the same duration and curve. Because the shell's own tests pump twice
  in one test, the harness now settles between pumps; the nine phase-1 assertions are unchanged.

Left for later: **Split View is still unstarted** (§9.5), so a pane is covered only by widget tests
at 475 x 669 — the rail centers in the reserved column there too, or in its own width where nothing
is reserved. `DisplayEnvironment.compactPane` is now unused by the shell: the system's column
answers the narrow-window question on its own, so the tighter margin it was for never shipped.

### 9.10 Phase 3 landed (2026-09-20)

4.4 is built and verified on the Duo simulator with a **debug** build, signed in, on the scratch
project (D8). What landed: a crease vocabulary in `lib/theme/layout.dart` (`creaseInBox`,
`isVerticalCrease`, `paneWidthFor`, `paneDividerWidth`, `CreasePadding`, `ColumnSnapPhysics`, and
`SideBySide`'s crease split), `lib/theme/dialogs.dart` with `dialogAlignmentFor` and
`showBoardhopDialog`, the four master/detail screens and the side-by-side diff on the fold, the
Kanban board and the sprint taskboard clear of the band, fourteen dialog helpers plus the work item
form and the type chooser through the wrapper, `CreasePadding` around every shell page, and
`tool/duo-drag` for long-press drags on the inner panel. Tests: `test/theme/layout_test.dart` grew
fifteen, `test/theme/dialogs_test.dart` is new (seven), and the wiki tree, root-tab, diff and board
tests gained a folded pose each, from the new `test/fixtures/duo_display.dart`.

**The crease is not at the page's centre, and that is the whole point.** The band is at
(455.5, 0) 40 x 669 in **window** coordinates, but the shell keeps 84 pt for the system's bar
column, so a pane splitting its own 867 pt box in half would miss the fold by 42 pt. Every helper
takes the band through `creaseInBox`, which converts it with the box's own `RenderBox`. That reads
the transform the **last** layout left, so the first layout of a box answers null and asks for one
more frame; from then on it is current, and because reading `DisplayScope` subscribes the box to it,
a fold rebuilds the box on its own. Every widget test here pumps twice for the same reason.

Measured on the device in the wide book pose, all through `idb ui describe-all`:

- **Work list and detail:** the list pane is **455.5** wide — the band's leading edge, not
  `0.42 * 867 = 364` — and the detail pane's placeholder centres at 681.25, the centre of
  495.5…867. The `VerticalDivider` is given the band's 40 pt, so its hairline lands on the crease
  and the 20 pt margins stay empty.
- **Home and the PR overview (`SideBySide`):** the end column starts at exactly **495.5** and is
  358 wide. Flat, both pages are one column — `ContentColumn` gives 840, under the 880 threshold —
  so the fold is what puts them side by side. That needed `creaseMinColumn` **320**, not half of
  `twoColumnMin`: the fold's halves of that box are about 442 and 358, because the crease is not
  centred in the content (above).
- **The new work item form:** opened from the Work bar's `+`, its fields start at **539.5**,
  entirely on the trailing panel.
- **The board:** the first column runs 135.5…455.5 and the second 495.5…815.5 — one card wall per
  panel, the band empty between them.

**Snapping alone was not enough for the boards.** A `ScrollPhysics` that rounds a fling to a lattice
of column boundaries leaves the board straddling the fold at rest, because the resting offset is
zero and zero is where the list starts. So the **leading padding** grows until a boundary lands on
the band unscrolled (135.5 pt here, which is `495.5 - 1 * pitch`), and zero is then a lattice point.
The gap between **every** pair of columns becomes the band's 40 pt rather than only the pair nearest
the fold: the pitch has to stay uniform for the lattice and for the drag auto-scroll's column
arithmetic, and a board that re-spaced itself as it scrolled would jump under the finger.

**A popup menu needs the half's edges, not the button's.** Constraining the type chooser's width to
one half did nothing: Flutter aligns a popup menu with whichever of `position`'s edges has less room
beyond it, so a `+` sitting 85 pt past the crease got a menu hung off *its* right edge, back across
the fold. Passing the **half's** left and right in `position` makes the same rule pin the menu
inside the half, on either side of the crease. `showBoardhopDialog` has the matching problem and
solves it by padding: it asks `showDialog` for `useSafeArea: false` and pads the route's box down to
the half already intersected with the system's insets, so a dialog on the leading panel does not
lose 84 pt to a bar column that is nowhere near it.

**What `CreasePadding` does, and does not.** With an active **horizontal** crease it grows
`MediaQuery.padding` — the inset a null-padding `ListView` consumes, that `scrollEndPadding` takes,
and that every bottom-anchored control already reads — to the band's near edge: the bottom inset
when the band is in the lower part of the box, the top inset when it is in the upper. Content at
rest and anything anchored to an edge then clears the fold. A list long enough to scroll still
travels **through** the band on its way past; nothing short of snapping every row could stop that,
and snapping a reading list would be worse than the fold. It also only wraps pages inside the shell,
so a pushed route (a work item, a pull request) is not covered.

Three things could not be verified on the device, with the reason:

- **The board's snap after a fling.** Flutter's `ScrollBehavior.dragDevices` on iOS is touch and
  stylus only, so a synthetic **mouse** drag does not scroll anything — it does drive
  `LongPressDraggable`, which is why the drag test below worked. idb's HID input does not reach the
  inner panel at all (§9.4), so there is no way to fling it. `ColumnSnapPhysics.snap` is unit-tested
  and the at-rest geometry is measured above.
- **`CreasePadding`'s effect**, for the same reason: extra bottom padding never moves top-aligned
  content, and the end of a list cannot be scrolled to. The pose itself is clean
  (`phase3-tall-book-*`) and the behaviour is covered by three widget tests.
- **Split View**, still unstarted (§9.5).

**A long-press drag across the fold works.** `tool/duo-drag holddrag` moved work item 15546 from
New to Active across the band and back again (the second attempt needed a retry — the first move's
rev had not been re-read, and the board said so and reloaded, which is the intended behaviour).
The proxy stayed under the pointer throughout. The scratch board is back as it was.

`tool/duo-pose` was fixed first: after Device Hub is relaunched the Duo shows inside its browser
window, whose title is then "Device Hub", so matching on `hasPrefix("iPhone Duo")` found nothing.
It now searches **every** window of the process for one carrying the pose buttons, with the title
as a fast path only, and the walk is depth-bounded at 16 because the tree has recursive nodes.
`list`, `book`, `open` and `rotate` all verified again, about 1.5 s each.

`tool/duo-drag` is new (§4.6). The accessibility tree is **not** the way to find the rendered
screen: Device Hub exposes it as an `iOSContentGroup` with the app's own elements under it, but
those frames are in an internal space — the group reads 626 x 890 at (285, 655) for a 951 x 669
display on a 1728 x 1117 desktop — and clicking there does nothing. Measuring the picture does
work: the hub paints the device on a flat dark canvas, so a `screencapture` of its window has one
bright rectangle in it, checked against the panel's aspect ratio and refused when it does not match.
That check fires often enough (Home's two columns, any dark page) that the reliable path is to
measure once and pin it: on this Mac `DUO_OX=959 DUO_OY=323 DUO_SC=0.6756`, which is what the whole
walkthrough used. Device Hub is brought to the front on every call — a synthetic click only reaches
the front window, and `screencapture -R` captures the desktop, so a terminal over the hub would be
measured instead of it.

**Verified, light and dark** (`.shots/duo/phase3-*`, each with a 400 px thumbnail): wide flat as the
control (`phase3-wide-flat-{home,pr}`), wide book (`phase3-wide-book-{work,home2,pr,board3,form,
typechooser2,drag,drag-back2}`), wide book in dark (`phase3-wide-book-dark`), tall book
(`phase3-tall-book-{board,pipelines,pr}`), and the restored state (`phase3-restored`). A full
circuit — wide flat, wide book, tall book, tall flat, dialogs, two drags — logged **no exception
and no overflow at all**. The Duo is left open, base rotation, light.

### 9.11 Phase 4A landed: corner clearance (2026-09-20)

Kelly's observation: in the wide pose and on the cover the project picker's icon sits about 9 pt
from the left edge and 14 pt from the top, on edges iOS reports as **zero** padding (the status
bar is in the trailing column), and the display's corners are rounded — 55 px on the inner panel,
59 on the cover — so the icon is cut by the curve in Device Hub's bezel and on hardware.
`SafeArea` cannot help, because the inset genuinely is zero.

**The API answers, and it is iOS 26, not 27.1.** `UIView.LayoutRegion.safeArea(cornerAdaptation:)`
with `view.edgeInsets(for:)` (the Swift refinement of `edgeInsetsForLayoutRegion:`, confirmed
against `UIKit.swiftmodule`'s `.swiftinterface` in the 27.1 SDK — `UIViewLayoutRegion.h` marks the
whole class `NS_REFINED_FOR_SWIFT`) is available from **iOS 26.0**, a release before the reserved
regions. There is **no public corner radius**: `UIScreen._displayCornerRadius` is private and
nothing in `UIScreen.h`, `UIWindow.h` or `UIWindowScene.h` replaces it, so the clearance comes
from the corner-adapted insets alone. What it answers, measured on the device in each pose
(l / t / r / b, points):

| Pose | window | `safeArea` | `cornerAdaptation: .horizontal` | `.vertical` | `margins` |
|---|---|---|---|---|---|
| Wide, inner | 951 x 669 | 0 / 0 / 84 / 34 | **16** / 0 / 84 / 34 | 0 / **16** / 84 / 34 | 20 / 0 / 84 / 34 |
| Cover, portrait | 466 x 678 | 0 / 0 / 84 / 34 | **2.3** / 0 / 84 / 34 | 0 / **17.3** / 84 / 34 | 20 / 0 / 84 / 34 |
| Tall, inner | 669 x 951 | 0 / 82 / 0 / 34 | **16** / 82 / **16** / 34 | 0 / 82 / 0 / 34 | 20 / 82 / 20 / 34 |

Three things to read off it. The two axes are **alternatives, not a pair**: the horizontal one
buys the clearance on the leading and trailing edges and leaves the top at zero, the vertical one
does the opposite, and a layout picks the axis its content runs along. A horizontal app bar whose
items sit in a row wants the **horizontal** one, so that is what the payload carries as
`cornerInsets`; taking the larger of the two per edge would inset twice for one corner. And the
number is **not the corner radius**: the cover's corner is the larger of the two in points (19.7
against 18.3) and its horizontal answer is the smaller by a factor of seven, so UIKit is answering
"how far in must a row start", not "how round is the corner". On the trailing edge the corner is
subsumed by the bar column's 84 pt, and in the tall pose the 82 pt status bar covers the top, so
**only the leading edge ever changes** on this hardware. No `Spacing.lg` fallback was needed and
none shipped: where nothing answers, `cornerInsets` is zero and every page stays exactly where it
was.

What landed: `cornerInsets` and a diagnostic `regionInsets` (all four regions) on the polled
`displayState` and the pushed `displayChanged`, with the corner in the push signature so a pose
that moves it pushes; `DisplayEnvironment.cornerInsets`, `regionInsets`, `chromeInsets(padding)`
(the larger of the two per edge) and the static `chromeInsetsOf` the shell uses; a
**Corner-adapted layout regions** card on the Display probe page showing all of it;
`GlassShellLayout.cornerInsets`, applied on a system edge to the top and the **non-rail** side
only and handed to the page through `MediaQuery.padding`, so its app bar takes the top itself (as
it takes the Dynamic Island's inset on a phone) and the shell's `SafeArea` takes the side, with
nothing to change in any page. Tests: three in `display_environment_test.dart` and five in
`glass_shell_layout_test.dart` (the corner on either edge, the cover's own smaller answer, a
sideways scroller taking it as padding, and no system edge — where the corner insets change
nothing at all).

**Two smaller findings.** The page's media query had to be re-declared **inside**
`_keyboardSafe`, not outside it: that wrapper builds a `MediaQuery.removeViewInsets` from the
shell's own context, so a media query nested under it that copies the ambient `mq` hands the page
back the keyboard inset the wrapper had just spent — caught by the existing landscape-keyboard
test, and now the rail branch zeroes the bottom view inset the way the bleeding branch always
did. And the page's content box on the inner display is **851 pt**, not phase 2's 867: the fade
cliff and the bar column are where they were, the 16 pt comes off the leading edge.

Verified on the device, debug build, signed in, scratch project (D8): `.shots/duo/`
`phase4-corner-{wide,cover}-{before,after}.png` (the top-left corner at 2x, "before" taken from
the phase 3 build first) plus `phase4-corner-{wide,cover}-after-hub.png`, which are crops of
**Device Hub's own window** (`screencapture -l <id>` with the id from `CGWindowList`) so the
bezel's corner mask is in the picture — that mask is what cuts the icon, and the shots show it
clear on both panels. `phase4-wide-work.png` is the Work page's app bar on the same inset, and
`phase4-probe-wide.png` is the Display page's new **Corner-adapted layout regions** card reading
the table above back off the device. `idb ui describe-all` puts the picker's button box at
**x = 16** where it was at 0. A full pose circuit logged no exception and no overflow.

**What this does not cover: a route outside the project shell.** The clearance is the shell's,
handed down through its own media query, so everything inside it takes it — including a page the
branch navigator pushes, such as a work item or a pull request. A route that is not in the shell
at all (the Organizations screen, every `/diagnostics/*` page, the launch flow) still lays out
against a zero inset and its back arrow still sits in the curve; `phase4-probe-wide.png` shows it.
Those pages follow the `SafeArea(top: false, bottom: false)` convention, which cannot help here for
the same reason it cannot help the shell, and giving them the corner means either a `DisplayScope`
read in each one or a wrapper above the router. It is a small, separate change, and §7 is the
place for it.

### 9.12 Phase 4B: the rich text editor under a live resize (2026-09-20)

The §4.5 test, on the device, scratch work item **15546** (`[phase2] tablet dialog HTML`, a
description with real `<b>`): open the form, open the description editor so the WebView is live,
then `book`, `open`, `rotate` (tall), `book`, `open`, `rotate 3` back to the wide pose, with a
temporary `debugPrint` counting editor builds, `onInit`s and disposes (removed again).

**Nothing breaks, and nothing needed fixing.** Across the whole circuit: **one** build, **one**
`onInit`, **no** dispose, the content visible and unchanged in every pose, and **no exception and
no overflow** in the log. Pressing **Done** afterwards round-tripped through the WebView —
`getText()` answered and the form's description card showed the text — so the editor was still
live at the end, not a stale picture. Folding with the form open and the editor closed was clean
as well. Shots: `.shots/duo/phase4-editor-{wide,book,open,tall,tall-book,back,roundtrip,
form-book}.png`.

Why it survives is worth writing down, because it is one line of code: `HtmlFieldEditor` keeps its
`HtmlEditor` in a **`late final`** field and `build` returns that same instance, so a rebuild
hands the element an identical widget and the WebView is never recreated. The `LayoutBuilder` in
`RichTextControl` is outside the slot and the slot's position in the `ListView` never moves, which
is the F3 rule. The mitigations §4.5 held in reserve — debouncing the width, snapshotting the HTML
— are not needed and were not built.

**The one imperfection: the slot's height is frozen.** `otherOptions: OtherOptions(height:)` is
read once, so after a rotation the WebView keeps the height the first layout gave it: 507 pt in
the wide pose against the 520 a fresh open in the tall pose would compute. Thirteen points, and
invisible — the blank space under the editor in the tall shots is the 520 pt clamp from F3, not
the staleness. Unfreezing it would mean building a new `HtmlEditor` widget with the new height,
which is exactly the recreation this design exists to prevent, so it stays frozen. Recorded as F6.

**A tooling note.** `idb ui tap --api ax` does not press an `AlertDialog.adaptive` button on iOS
(the "Discard your changes?" confirmation ignored four presses of `Discard` while `Close` and
`Done` worked in the same session), and an ax tap by **coordinates** on the inner panel answers
"No translation object returned for simulator". `tool/duo-drag click X Y` through Device Hub does
it. idb's `describe-all` also keeps reporting the **Application** element at the pre-rotation size
while every child is in the new one, so trust the children's frames, not the root's.

### Phase 4 landed

4.3's corner clearance (A) and 4.5's live-resize test (B) are done, on the device, in the poses
above. Phase 4 changed `ios/Runner/AppDelegate.swift`, `lib/core/display_cutout.dart`,
`lib/core/display_environment.dart`, `lib/features/diagnostics/display_probe_page.dart`,
`lib/features/projects/glass_shell_layout.dart` and `lib/features/projects/project_shell.dart`,
with eight new tests. Nothing in the rich text editor changed: B was a test, and it passed.

Left for later, with the reason: **Split View** is still unstarted (§9.5), so the corner insets of
a pane are unmeasured — a pane's inner edge is not a display corner at all, and this build simply
takes whatever iOS answers there. And the **rich text editor's dialog does not move to one half**
when the fold happens while it is already open: `showBoardhopDialog` settles the alignment when
the route is shown, and `openRichTextEditor` does not go through it at all. Both are phase 3's
scope, not a phase 4 regression; §7 is the place for them.

### 9.13 Phase 4b landed: the chrome above the router, the dialogs that follow a fold (2026-09-20)

The three things §9.11 and §9.12 left open, closed together.

**1. Every route outside the project shell.** The shell hands its pages a corner-adapted
`MediaQuery.padding` and wraps them in a `CreasePadding`; a route that is not in the shell — the
Organizations screen, the project list, the launch flow, Settings, every `/diagnostics/*` page —
and a route pushed **over** the shell — the standalone work item, the pull request and its file
diff, a wiki page, the chart focus view — got neither, so its back arrow sat in the curve at
x = 4 and its content ran through the fold. `WindowChrome` (`lib/theme/layout.dart`) now does both
once, in `MaterialApp.builder`, above the router, so a route added later cannot forget it.

Which leaves not insetting the shell's own pages twice, and the brief's suggestion — a marker the
shell provides, checked by the wrapper — **cannot work**: `MaterialApp.builder`'s child *is* the
Navigator, so every route, shell included, is below the wrapper and nothing below can be asked.
The question is turned round instead. `WindowChrome` publishes the padding it found before it
touched it (a private `_WindowPadding` inherited widget) and `ProjectShell.build` takes it back
with `WindowChrome.unwrap`, so the rail's column, the fade and the bottom bar are computed from
exactly the numbers iOS reports, as before. That also keeps Android's Material shell and the tall
pose's bottom bar untouched: without the unwrap, a `CreasePadding` applied above the router would
have handed the shell a 495.5 pt bottom inset in the tall book pose and floated the glass dock
half way up the window.

The corner clearance follows the shell's rule exactly (`GlassShellLayout._corneredInset`): **only
where iOS names a vertical bar edge**, and there only on the top and the side away from that bar.
Every other device — every iPhone and iPad — keeps the padding iOS reports to the point, because
the corner-adapted region answers on them too (it is iOS 26 API, §9.11) and taking it would move
every page in the app sideways for a curve the layout has always cleared. In the Duo's **tall**
pose the bar edge is `unspecified` (§2), so nothing changes there either and a back arrow still
sits at x = 4 with a 16 pt corner beside it — the same as the shell's pages in that pose, so it is
phase 4A's scope, not a phase 4b regression.

**2. Dialogs that are open when the fold happens.** `showBoardhopDialog` settled the placement when
the route was shown. It is built inside the route now, in a `_DialogPlacement` that reads
`DisplayScope` and moves on `Durations.normal` / `Motion.standard`. The half it moves *to* is still
the one it was opened on: `near`, or the opening widget's box, read **at show time** while that
widget is still on screen and handed back on every rebuild as `nearBox` — inside the route
`context` is the dialog's own full-window box and would answer nothing.

The move is an `AnimatedPadding`, not the `AnimatedAlign` the plan named, because position and size
change together: a dialog that fills what it is given — the rich text editor — has to be *resized*
to the half, and an `Align` can only slide it. The same padding is the safe area when nothing is
folded, which is what `useSafeArea: true` used to put there once and for all; `showDialog` is now
always asked for `useSafeArea: false`, and the flat case is pixel-identical to before (the existing
test still measures the dialog's centre at (951 − 84) / 2).

`openRichTextEditor` goes through the wrapper too — it was the one dialog in the app calling
`showDialog` directly — and its `maxHeight` comes from a `LayoutBuilder` on the box it is given
rather than from `MediaQuery.sizeOf`, which on a fold would be twice the room there is. The
`RichTextEditor` instance is built once outside the builder, so a fold hands the element the
identical widget and the WebView is never recreated (the F3 rule, §9.12).

**Measured on the device**, debug build, signed in, scratch project (D8), light, all through
`idb ui describe-all`:

| Where | Before | After |
|---|---|---|
| Display probe, wide, back arrow / body | 4 / 0 | **20 / 16** (body 851 wide) |
| Diagnostics index, wide | — | 20 / 16, body 851 |
| Organizations ("Accounts"), wide | — | title 32, body 16, 851 wide |
| Pull request file diff, wide | — | back 20, body 21.5 |
| Standalone work item, wide | — | back 20, tabs from 16 |
| Same pages on the **cover** | — | back 6.3, body **2.3**, 379.7 wide |
| Tall book, standalone work item's comment composer | y = 861 | **y = 399.5** (bottom 447.5, band top 455.5) |

The 16 and the 2.3 are §9.11's measured corner-adapted insets read back through a page that never
sees them, and 20 = 16 + the `AppBar`'s own 4 pt around its leading icon.
`phase4b-corner-{before,after}.png` are the same crop of the Display probe's top-left corner from
the phase 4 build and this one: the chevron and the card move right by exactly 48 px (16 pt at @3x).
The composer's 399.5 is `951 − 495.5 − 48 − 8`, the `CreasePadding` bottom inset (`951 − 455.5`)
working on a route the shell never wrapped.

**The dialogs, on the device.** The new work item form was opened flat and **then** folded: it
walked onto the trailing half (fields from 539.5, the half being 495.5…867 less `Spacing.xl` and
the `Dialog`'s own inset). Unfolded again it walked back to the centre. The description editor was
then opened flat and folded with it open: it went to the **leading** half (80…343.5), because the
description card it was opened from is 377.5 pt wide — small enough to count as a control — and
sits there. Both dialogs on screen at once, one per panel, neither across the band
(`phase4b-wide-book-editor.png`). Pressing Cancel and Close afterwards round-tripped normally, so
the editor was live, not a stale picture.

**Shots** (`.shots/duo/`, each with a 400 px thumbnail): `phase4b-wide-{orgs,diagnostics,probe,
prdiff,wi-standalone,form,flat-form,flat-editor}`, `phase4b-wide-book-{form,editor}`,
`phase4b-tall-book-wi`, `phase4b-cover-{orgs,diagnostics,wi}`, `phase4b-corner-{before,after}` and
`phase4b-restored`. The walkthrough — wide flat, wide book, tall flat, tall book, the cover, two
dialogs through a fold and back — logged **one** exception, and it is not this phase's: the
**Diagnostics index's own app bar overflows on the cover**, 431.7 pt of back arrow and eight probe
icons in 379.7 pt. It overflowed by 49.7 before this change and by 52 after it (the 2.3 pt corner),
on a page that only exists in a debug build; moving the probes into an overflow menu is the fix and
is not part of this phase. A second, clean run then repeated the whole circuit without the cover's
diagnostics index — the shell, the work item form dialog folded and unfolded, the Display probe
(outside the shell) folded and unfolded, and wide flat / wide book / tall flat / tall book / back —
and logged **no exception and no overflow at all**.

**One thing seen and not fixed, with the reason.** `WorkItemDetailPage` has no
`SafeArea(top: false, bottom: false)` of its own — it was written as a shell page, and the shell's
SafeArea covered it. Opened as the **standalone** route over the shell it therefore ignores the
84 pt bar column and its comments run under the stacked status bar on the cover
(`phase4b-cover-wi.png`). That predates this phase (the standalone route has never been inside the
shell's SafeArea) and it is a per-page fix, not one the wrapper can make: a page that *does* bleed
sideways on purpose must keep bleeding. Same for the missing column fade there, which is the
shell's and stays the shell's.

Tests: `test/theme/window_chrome_test.dart` is new (seven — the corner on either edge, no system
edge, the crease, a flat display, and the shell's unwrap for both), `test/theme/dialogs_test.dart`
grew one that folds and unfolds under an open dialog and checks it is still in flight half way
through the motion, and `test/features/rich_text_dialog_test.dart` is new (three). `test/fixtures/
duo_display.dart` learned `barEdge`, `cornerInsets` and the measured `wideCorner`.
1953 tests green, `flutter analyze` clean.

Changed: `lib/app.dart`, `lib/theme/layout.dart`, `lib/theme/dialogs.dart`,
`lib/features/projects/project_shell.dart`,
`lib/features/work_items/form/controls/rich_text_control.dart`.

### 9.14 Split View, left pane (Kelly started it by hand, 2026-09-20)

Kelly put Boardhop on the left and Safari on the right. Measured with the Display probe and
`simctl pbpaste` (`.shots/duo/split-left.json`, `split-left-home.png`, `split-left-probe.png`):

- Window **469 x 669 pt**, `compact`, `orientation` portrait, `verticalBarEdge` **leading**,
  `railSide` left, `compactPane` true. Answers 12b appendix question 3: the pane is compact.
- `padding` **0 / 0 / 8.7 / 34**: iOS reports **no leading inset** for the bar column in a pane
  (there is no status cluster on that edge; the cluster stays on the display's right, in Safari's
  column), and 8.7 pt on the divider side. So the shell's bare rail sits in its own 72 pt column
  on the outer edge with content from 72 + 16 (the corner inset, 16 on the leading edge again).
  Visually right: the items line up on the pane's outer edge like Safari's on its own.
- The division region is still reported, **inactive**, clipped to the pane: x 455.5 to 469, so
  13.5 pt of the 40 pt band fall inside the left pane. `folds` is true, `crease` null. If the
  device is folded while in Split View the active band will lie across the divider, mostly outside
  the pane; nothing in the pane should split (each pane is one panel) and `paneWidthFor` will
  ignore it because 455.5 is above every pane maximum.
- `pushes` 4 while entering Split View; `metricsChanges` 1 (the resize itself).
- **Right pane** (Kelly swapped the sides; `split-right.json`, `split-right-home.png`,
  `split-right-probe.png`): 469 x 669, `compact`, `verticalBarEdge` **trailing**, `railSide`
  right; `padding` **8.7 / 0 / 84 / 34**, so here the 84 pt status column *is* reported and the
  bare rail sits inside it under the cluster exactly as on the full display; 8.7 pt on the
  divider side again. The division region is inactive and clipped to x 0 to 13.5. Two
  occlusions: the status cluster **active** at (385, 0) 84 x 120, and an **inactive** one at
  (195.3, 21) 58 x 37 that is most likely the front camera housing (inactive because nothing is
  drawn there in this pose). `pushes` 7, `metricsChanges` 6 across the swap. The accessibility
  backend (`idb ui tap --api ax`, `describe-all`) sees only the leading app in Split View, so the
  right pane was driven with `tool/duo-drag click` (mapping `DUO_OX=877 DUO_OY=315 DUO_SC=0.7003`).
  Both panes verified by eye: the rail on each pane's outer edge, D1 holds in Split View.
- Question 2 of 12b (is the divider draggable) is still Kelly's to answer by trying it.
