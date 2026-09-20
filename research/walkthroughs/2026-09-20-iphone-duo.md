# iPhone Duo walkthrough — the fold, the four poses and the cover, 2026-09-20

Phases 0 to 5 of `research/23-iphone-duo-adaptation.md`, run the day after Xcode 27.1 and the
iPhone Duo simulator landed on the Mac. Device: iPhone Duo simulator
`58DEB6C0-6F8A-46A1-AAB5-217C2A2C5B20`, iOS 27.1, **debug** builds from `flutter run`
(`--dart-define-from-file=.env`), signed in as Kelly and on the scratch project **DevOps Mobile
App** in puremedia (D8 — nothing here was checked against demo data).

**Writes went only to the scratch project.** One work item, **15546** (`[phase2] tablet dialog
HTML`), was dragged from New to Active and back on the Kanban board to prove a long-press drag
across the crease (the second move needed a retry, because the first move's rev had not been
re-read and the board said so and reloaded — the intended behaviour). Its edit form and
description editor were opened for the live-resize test and **discarded**, and the new-work-item
form was opened twice and cancelled both times, so no field was saved. Nothing else was written,
and nothing outside "DevOps Mobile App" was touched.

**Poses were driven from outside the guest**, not by tapping the screen: `tool/duo-pose
closed | book | open | rotate [n]` presses Device Hub's own buttons through the Accessibility API
(research/23 §1.1), about 1.5 s each, and a pose has landed when the expected panel stops
capturing black. Input on the inner panel is `press "<label>"` (idb's accessibility backend) or
`tool/duo-drag` (mouse events into Device Hub's window); **idb's HID taps only ever reach the
cover**. Layouts were read back with `idb ui describe-all`, whose frames are in window points, and
whole poses with the Display probe's *Copy as JSON* plus `xcrun simctl pbpaste`.

Screenshots are in `.shots/duo/` (gitignored), each with a 400 px `_s.png` thumbnail; every claim
below names the ones it rests on.

**Console:** a full pose circuit — wide flat, wide book, tall flat, tall book, the cover and back
— logged **no exception and no overflow** at the end of phases 2, 3, 4b and 5. Two exceptions were
found and fixed during the run (§"What broke"), and one more, the Diagnostics index's own app bar,
was found in phase 4b and fixed in phase 5.

`flutter analyze` clean, suite **1957 green** at the end of the run.

---

## What was checked, pose by pose

| Pose | Window | What was walked | Shots |
|---|---|---|---|
| **Open, wide, flat** (`expanded`) | 951 x 669 | Home, Work list and detail, Boards, the PR overview, the work item form, the Display probe, Diagnostics; light and dark | `phase2-open-wide-flat-{home,board}-{light,dark}`, `phase2-open-wide-flat-work-light`, `phase3-wide-flat-{home,pr}`, `phase4b-wide-{orgs,diagnostics,probe,prdiff,wi-standalone,form}` |
| **Open, wide, book** (fold active, vertical crease) | 951 x 669 | the same pages with the crease live: panes, `SideBySide`, the board, the type chooser, two dialogs, a drag across the band; light and dark | `phase3-wide-book-{work,home2,pr,board3,form,typechooser2,drag,drag-back2,dark}`, `phase4b-wide-book-{form,editor}` |
| **Open, tall, flat** (`medium`) | 669 x 951 | Home and the probe with the bar edge `unspecified` — the glass bar stays along the bottom | `phase2-open-tall-flat-home-{light,dark}`, `phase3-tall-home`, `phase5-tall-diag` |
| **Open, tall, book** (horizontal crease) | 669 x 951 | the board, Pipelines, a pull request, the standalone work item's composer, `CreasePadding` | `phase3-tall-book-{board,pipelines,pr}`, `phase4b-tall-book-wi`, `phase5-tall-book-diag` |
| **Closed (cover)**, portrait and landscape | 466 x 678 / 678 x 466 | Home, the board scrolled to its last column, Organizations, Diagnostics, the standalone work item | `phase2-closed-portrait-home-{light,dark}`, `phase2-closed-board-scrolled`, `phase4b-cover-{orgs,diagnostics,wi}`, `phase5-cover-{wi,diag,diag-menu}` |
| **Split View** (both panes, Kelly by hand; right pane: `split-right-home`, `split-right-probe`, padding 8.7/0/84/34, bar edge trailing, rail inside the status column) | Home, Display probe | 469x669 pt compact, bar edge leading, no leading inset: the bare rail takes its own 72 pt column on the outer edge; content from 88; the divider side reports 8.7 pt; the fold's band is reported inactive and clipped at 455.5 | `split-left-home`, `split-left-probe` |

Regression, unchanged by the whole adaptation: iPhone 17 portrait and landscape and iPad Pro 13"
portrait and landscape (`phase2-regress-{iphone,ipad}-{portrait,landscape}`), debug logs clean.

## What was measured

Every number in research/23 §2 came off the device through the Display probe at
`/diagnostics/display`, pose by pose (`{closed-portrait,closed-landscape,open-wide-flat,
open-wide-book,open-tall-flat,open-tall-book}-diag-{inner,outer}` plus the `.json` beside each).
The four that decided the design:

- **The window is not where the content is.** `MediaQuery.padding` is **84 pt** on the edge that
  carries the stacked status bar (82 pt on top in the tall pose), 34 pt for the home indicator and
  **zero everywhere else**, in every pose. The rail lives inside that 84 pt column, so the page has
  **867 pt** on the inner display and **382** on the cover — 851 and 379.7 once the corner
  clearance comes off the leading edge (`phase4b-corner-{before,after}`, the same crop 48 px / 16 pt
  apart).
- **The crease is a zero-width line with a 40 pt keep-out band**, vertical at x 475.5 in the wide
  pose and horizontal at y 475.5 in the tall one — across the display's **longer** edge, which is
  the opposite of what research/12b implied. It is reported in **window** coordinates, so a pane
  splitting its own 867 pt box in half would miss the fold by 42 pt: everything converts the band
  with `creaseInBox` first.
- **Where things actually landed** (`idb ui describe-all`, wide book pose): the Work list pane
  **455.5** wide, the detail pane centred at 681.25; `SideBySide`'s end column starting at exactly
  **495.5**; the board's first column 135.5…455.5 and its second 495.5…815.5, one card wall per
  panel; the new work item form's fields from **539.5**, entirely on the trailing panel; the rail's
  four destinations at x 873 w 72, centre **909**, the reserved column's own centre.
- **Corner-adapted insets** (iOS 26 `edgeInsets(for:)`, `phase4-probe-wide`): 16 pt on the leading
  edge of the inner display, **2.3** on the cover, 0 on every edge already covered by the status
  bar column or the home indicator. The two axes are alternatives, never a pair, and the number is
  not the corner radius — the cover's corner is the larger in points and its answer is seven times
  smaller.

## What broke, and what was fixed along the way

- **The channel answered nothing at all** (phase 0). `FlutterAppDelegate.window` is nil in this
  scene-based app, so the reserved regions, the bar edge and the hinge were all empty in every
  pose. Going through the active `UIWindowScene`'s key window fixed all three at once; the
  `FlutterViewController`'s own view then answers every query.
- **An unfold pushed a stale region** (phase 1). UIKit flips a division region's `isActive`
  *after* the hinge has reported the new status, and on an unfold nothing follows — no layout
  pass, no metrics change, no further hinge update — so the app stayed laid out around a crease
  that was no longer there. A settling re-read 0.35 s after the last push of a burst, sent only
  when a signature of the regions, the bar edge, the orientation and the hinge changed, closes it
  at no cost when nothing moved (`phase1-{open-wide,book,open,tall,tall-book,restored}`).
- **A 77 px `RenderFlex` overflow at startup** (phase 2): for one frame the Duo reports a window
  about 140 pt tall, and four fifths of that is less than the vertical rail's destinations need.
  `GlassNavigationRail.lengthFor` now gives the shell the rail's own length and the box is never
  shorter; it overhangs the window instead of squeezing.
- **The rail was rebuilt twice on Kelly's word** (phase 2). The glass pill on the system edge was
  rejected from the first screenshots — too wide for the column, and its icons not under the
  status cluster the way Apple's own vertical bar is — so the rail went **inside** the reserved
  column, bare, with only the selected destination keeping its capsule (D10). Then content passing
  under the bare glyphs read as clutter on the Boards wall, so every page under a system edge fades
  out on a `Spacing.md` cliff at the column's inner boundary (D11); a `ShaderMask` takes no taps, so
  the board still scrolls under it and its last column still comes fully into view
  (`kelly-boards-{closed-portrait,open-wide}-{post,fade}`, `phase2-closed-board-scrolled`).
- **Snapping alone did not keep the board off the fold** (phase 3): a fling lattice leaves the
  resting offset at zero, and zero is where the list starts, so the leading padding grows until a
  boundary lands on the band unscrolled and the gap between **every** pair of columns becomes the
  band's 40 pt (`phase3-wide-book-board3`, `phase3-wide-book-board-snap`).
- **A popup menu needs the half's edges, not the button's** (phase 3): Flutter aligns a menu with
  whichever of `position`'s edges has more room, so constraining its width did nothing and the type
  chooser hung back across the fold. Passing the half's left and right pins it
  (`phase3-wide-book-typechooser2`).
- **The project picker's icon sat in the rounded corner** (phase 4A, Kelly's eye, not a log line):
  9 pt from a left edge iOS reports as zero padding, cut by the bezel's corner mask. Fixed from
  the corner-adapted layout region, which is iOS **26** API, a release before the reserved regions
  (`phase4-corner-{wide,cover}-{before,after}` and the `-after-hub` crops, which include Device
  Hub's own bezel mask because that mask is what cuts the icon).
- **Every route outside the shell had neither clearance nor crease padding** (phase 4b): the
  Organizations screen, the diagnostics pages, and a route pushed over the shell such as a pull
  request. `WindowChrome` in `MaterialApp.builder` does both once, above the router, and the shell
  unwraps the padding it publishes so its own rail, fade and bottom bar still compute from what iOS
  reports (`phase4b-wide-{orgs,diagnostics,probe,prdiff}`, `phase4b-tall-book-wi`).
- **A dialog open across a fold stayed across it** (phase 4b): the placement was settled when the
  route was shown. It is built inside the route now and moves on `Durations.normal` to the half it
  was opened on. The form walked onto the trailing half and the description editor onto the
  leading one, both on screen at once and neither across the band
  (`phase4b-wide-book-{form,editor}`).
- **The Diagnostics index's app bar overflowed on the cover by 52 pt** (found in phase 4b, fixed
  in **phase 5**): a back arrow, eight probe icons and Copy report in 379.7 pt. On a compact width
  the probes fold into one menu behind a flask icon; the Display probe and Copy report stay icons
  at every width (`phase5-cover-diag`, `phase5-cover-diag-menu`; `phase5-wide-diag` and
  `phase5-tall-book-diag` keep every icon). The menu takes `kTrailingMenuOffset` and opens inside
  the visible area.
- **The standalone work item ran under the stacked status bar** (found in phase 4b, fixed in
  **phase 5**): `WorkItemDetailPage` was written as a shell page and had no `SafeArea(top: false,
  bottom: false)` of its own, so pushed over the shell it ignored the 84 pt column. The standalone
  route insets itself now and the embedded pane is untouched. Measured after the fix: the comments
  end at **382** on the cover, exactly the column's boundary, where they used to run to 466
  (`phase5-cover-wi` against `phase4b-cover-wi` — the first comment's timestamp was under the
  Wi-Fi glyph and is not now); in the wide pose the body's scroll area is 21.5…861.5 and the back
  arrow at 20 (`phase5-wi-open`).

## Still open

- **Split View: both panes measured** after Kelly started it by hand (research/23 §9.14); only the divider-drag question stays open. Originally: It cannot be started from a script: idb's HID input does not
  reach the inner panel at all, and although a synthetic `CGEvent` swipe through Device Hub's
  window does open the app switcher, the card would not drag to either edge (research/23 §9.5).
  Device Hub has no Split View button. So the two pane rows of §2, a pane's size class, the
  fixed-50/50 claim and the corner insets of a pane's inner edge are all unmeasured; the rail and
  the layouts are covered there by widget tests at 475 x 669 only. **Kelly starts it by hand once**
  and the rows fill in one pass with `duo-pose` and the probe's *Copy as JSON*.
- **The board's snap after a fling** was never exercised on the device. Flutter's iOS
  `dragDevices` are touch and stylus, so a synthetic mouse drag scrolls nothing (it does drive
  `LongPressDraggable`, which is why the drag test worked), and idb cannot reach the inner panel.
  `ColumnSnapPhysics` is unit-tested and the at-rest geometry is measured; the feel of a fling
  landing on the lattice needs hardware.
- **`CreasePadding`'s effect** is likewise unproven on the device, for the same reason: extra
  bottom padding never moves top-aligned content, and the end of a list cannot be scrolled to.
  Three widget tests cover it and the tall book pose itself is clean (`phase3-tall-book-*`).
- **Corner clearance in the tall pose is unspecified by design, and it shows.** The bar edge is
  `unspecified` there, so neither the shell nor `WindowChrome` applies the corner inset, and a back
  arrow sits at x 4 with a 16 pt corner beside it. It is phase 4A's scope, not a regression, and it
  wants a decision from Kelly before the rule is widened.
- **The rich text editor's slot keeps the height of its first layout.** `OtherOptions(height:)` is
  read once, so after a rotation the WebView is 507 pt where a fresh open would compute 520.
  Thirteen points and invisible, and unfreezing it would mean building a new `HtmlEditor` — exactly
  the recreation the design exists to prevent. Recorded as F6 in the spikes README.
- **Nothing has been seen on hardware.** The device ships 2026-10-23; the simulator paints no
  crease, shows no Dynamic Island cutout, and its bezel corner mask is Device Hub's drawing of one.

## Left as found

The Duo is **open, base rotation, light**, on Home in the scratch project
(`phase5-restored`). The scratch board is back as it was: 15546 is New again, and no work item,
comment or PR was left changed.
