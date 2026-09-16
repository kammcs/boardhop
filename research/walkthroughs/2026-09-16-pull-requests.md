# Pull requests walkthrough — iPhone 17 and iPad Pro 13-inch, 2026-09-16

Phase P-D of research/22 (acceptance for the pull requests second pass).
Devices: iPhone 17 simulator `9CB22607-F6D0-4C47-8B2D-4AC4F60A6A31` and iPad
Pro 13-inch (M4) `929DE352-434C-4CE6-BB96-5C34212741E8`, **debug** builds from
`flutter run` (consoles `iphone.log` and `ipad2.log` in the session
scratchpad). Signed in as Kelly (puremedia).

**Writes went only to the scratch project "DevOps Mobile App"**, all of them on
**PR 8401** (`spike/w39-20260916-043401-a` → `scratch/policy-target`, policies
192 minimum-reviewers and 193 merge-strategy): auto-complete set and cancelled
three times, draft and publish twice, retarget to `main` and back twice,
restart merge, title edited and restored, the project team added as a reviewer
/ made optional / removed, one label added and removed, #15545 unlinked and
relinked, one comment liked and unliked twice, and one commit pushed to the
source branch by the new spike `w41_push_to_8401.py`. Nothing was written
anywhere else. One client pull request and one client project were **read**
only (Overview scrolled, nothing tapped that writes); no client screenshot is
named here and no client content appears in this document beyond the fact that
six required-reviewer names rendered.

Screenshots live in `.shots/` (gitignored) under the `pd` prefix.

**Console: no `EXCEPTION`, no `overflowed`, no `RenderFlex`, no assert** on
either device over the whole run (`grep -ciE` on both logs: 0).

**Three defects were found on the devices and fixed here**, one of them P-C's
own open item; each has a test. `flutter analyze` clean, suite **1824 green**
(3 new).

**8401 was left as asked:** active, auto-complete cancelled, target
`scratch/policy-target`, title `spike w39 PR A (20260916-043401) retitled`,
one label, no reviewers, #15545 linked. Verified by a final read.

---

## Per acceptance item (research/22 §5)

| # | Item | Verdict |
|---|---|---|
| 1 | Merge box, auto-complete set / banner / cancel / remembered / policy-limited merge types | **pass**; the Complete-after-a-second-vote state **not demonstrable** |
| 2 | Draft confirm + publish, retarget both ways, restart merge, edit title | **pass** |
| 3 | Reviewers: team, required, optional, remove; required-reviewer names on a client PR | **pass**; reset vote / flag / decline **not demonstrable** |
| 4 | Labels, work item unlink/link #15545, Share | **pass** |
| 5 | Phone pill, modes, indicator, Next file / Back to files, wrap, viewed; iPad pair, shortcuts, side-by-side; viewed cleared by a new push | **pass, one defect fixed** |
| 6 | Comment tools, Activity chip, and the Comments-tab `&line=` jump | **pass, P-C's open item closed** |
| 7 | Inbox auto-complete badge and reason labels | **pass**; the reviewer reason labels **not demonstrable** |
| 8 | Both simulators, both themes, xxxL, landscape side insets, side-by-side performance | **pass, one defect fixed** |

---

### 1. Merge box and auto-complete — pass, one state not demonstrable

`pd02`: the Overview's merge box lists the policies required-first — **No
merge conflicts** (green), **Minimum number of reviewers · 1 approval
required** (pending, `required`), **Require a merge strategy · Squash allowed**
(green, `required`), then the non-blocking `boardhop / spike-iter` status —
with **Set auto-complete** as the primary button.

`pd03`/`pd04`: the completion sheet limits the merge type exactly to policy
193 — **Merge (no fast-forward)** and **Squash commit** live, **Rebase and
fast-forward** and **Semi-linear merge** greyed with "Not allowed by policy".
Delete source branch, Complete linked work items and Customize merge commit
message are all on with a remembered message; **Wait for optional policies
too** is correctly disabled with "The target has no optional policies" (both
of 8401's policies are blocking); **Override policies** carries the honest
"Only some accounts may; the service refuses the rest".

`pd05`: after Set auto-complete the banner reads "Auto-complete set by Kelly
Kamm · waiting on 1 check · squash commit" with **Cancel**. `pd14`: Cancel
clears the banner and the button returns to Set auto-complete. `pd15`: the
sheet reopens with every option still as it was — the service keeps
`completionOptions` after the cancel, which is where the sheet reads them from.

**Not demonstrable:** 8401's Complete state needs a *second* reviewer's
approval to satisfy policy 192, and Kelly is the creator and the only identity
on this tenant. What *was* shown is that the button is genuinely state-driven
rather than hard-coded: on **8334**, whose target `main` carries no blocking
policy, it reads **Complete** (`pd08`), and 8401 itself read **Complete** for
as long as it was retargeted to `main` (`pd25`).

### 2. Draft, publish, retarget, restart merge, title — pass

- `pd17`: Mark as draft confirms with R4's exact warning — "Reviewers stay on
  the pull request, but every vote already cast is reset."
- `pd18`: as a draft the chip appears, both policies fall to **Not evaluated
  yet**, and the button becomes **Publish**. `pd21`: Publish restores all of it
  with no confirm, as R4 asks.
- `pd22`–`pd28`: Change target branch → `main` and back. The merge box
  re-evaluates each time (`main` has no policies, so only the merge state and
  the status show) and `pd52` shows the iteration picker labelling every
  iteration `push` or **`retarget`**.
- `pd29`: Restart merge takes the state from "Merge check pending" back to
  "No merge conflicts".
- `pd30`–`pd34`: Edit opens a title + description sheet; " P-D" was appended,
  saved, then removed and saved again. The title is back to what it was.

One thing to know for anyone driving this by script: the branch picker
autofocuses its search field, so the keyboard raises the sheet and every row
moves about 45 dp up between the sheet opening and settling. A tap timed
against the pre-keyboard layout picked the row below the one intended — the
PR's own source branch — and the service answered
`GitPullRequestRetargetSourceSameAsTarget`, which the page showed verbatim.
That is a driving hazard rather than a defect; the picker offering a branch the
service will refuse is noted as open below.

### 3. Reviewers — pass; three actions not demonstrable

`pd36`: the add sheet searches people *and* teams, lists **Teams** first with
the project team, and carries the **Required** toggle with its explanation.
`pd37`: the team lands as "[DevOps Mobile App]\DevOps Mobile A… · No vote ·
Required · team". `pd38`: its per-reviewer menu offers exactly **Make
optional** and **Remove** — correctly no Reset vote (no vote to reset), no
Flag or Decline (a container cannot, and Kelly is the author). `pd39`: Make
optional flips the line to "Optional". `pd40`: Remove takes it back to
Reviewers (0).

**Not demonstrable:** reset vote, flag for attention and decline all need a
reviewer who is not the author, and Kelly is the only identity. w39 exercised
all three against the API — the Activity chip on 8401 still lists "Kelly Kamm
voted 10", "Vote of Kelly Kamm was reset" and "Kelly Kamm declined to review"
from that run (`pd99`) — but not one of them was driven from the app.

**Required-reviewer names, closed.** The scratch branch carries only
minimum-reviewers, which names nobody, so a new read-only probe
`s66_required_reviewer_policies.py` swept the organization for the *Required
reviewers* type (`fd2167ab-…`, easy to confuse with `fa4e907d-…`, which is
Minimum number of reviewers and carries no names). Five exist, all in one
client project, and the probe then listed the active pull requests targeting
their branches. One of those was opened read-only: `pdb3` shows the merge box
rendering **Required reviewers · 6 required reviewers** followed by the
**"Required by policy"** block with all six names resolved and their vote state
beside each. That closes NEXT-STEPS item 8's open note. The same screenshot
incidentally shows the required-first ordering against a real policy set —
a failing merge-strategy policy in red, an expired build, comment
requirements, work item linking, and a not-applicable status with a ⊖.

### 4. Labels, work items, Share — pass

`pd41`: the labels editor lists the project's tag pool as suggestions
(`boardhop`, `boardhop-spike-2`, `iospad`, `iosphone`, `phase1`, `spike`) with
the existing chip and its ×. `pd42`: adding `iosphone` drops it from the
suggestions. `pd43`: the × removes it and the Overview is back to Labels (1).

`pd44`/`pd45`: unlinking #15545 confirms with "The work item itself is not
changed" and drops the section to (0). `pd46`–`pd48`: the `#` picker lists the
project's items, filters on `15545`, and relinks it.

`pd49`: Share opens the system sheet with the PR's `dev.azure.com` web URL.

### 5. Diff navigation — pass, one defect fixed

**The phone, which P-C never saw.** `pd54`: the floating pill draws bottom
trailing over the diff, above the safe area. At the top of the file the ▲ side
expands into R7's "Previous file: thr…" and the rest reads "📄 1 / 2 ·
Changes ⌄". `pd55`: ▼ steps to change 2 / 2 and the ▼ side becomes "Next file:
two.txt". `pd56`: the indicator is the mode control — **Changes (2)**,
**Comments (5)**, **Files (4)**. `pd57`: Comments mode reads "💬 4 / 5 ·
Comments" as a compact centred pill with both arrows. `pd58`/`pd59`: it slides
away on scroll-down and comes back on scroll-up. `pd60`: it hides for the
new-thread composer. `pd65`–`pd67`: in Files mode it reads "3 / 4 · Files",
▼ loads **two.txt** in place with "4 / 4 · Files" and **Back to files**, and
that returns to the Files tab.

Also on the phone: `pd61` the app-bar menu (**Comment on file**, **Wrap long
lines**, **Side by side**), `pd62` wrap reflowing the thread cards and comment
text, `pd63`/`pd64` the viewed check in the app bar toggling both ways.

**The iPad.** `pdb8`: the nav pair moves into the app bar exactly as R6 asks —
"◀| 📄 1 / 2 · Changes ⌄ ✅ ••• it. 10 ▾". `pdc0`: **Side by side** gives two
synced panes, old on the left and new on the right, with the right-side threads
under the right pane and the left-side thread (on removed line 5) under the
left. `pde1` is the same in dark.

**Keyboard shortcuts (R16), all four families.** Driven through
`idb ui key`, which takes **HID usage codes**, not Linux keycodes — `n` is 17,
`v` 25, `[` 47, `]` 48, F7 64. `pdc1`: `v` flips the app bar's viewed check to
an outline. `pdc2`: `n` switches the mode to Comments and steps to 2 / 5.
`pdc5`: `]` loads **two.txt** and the indicator becomes "– / 0 · Comments"
with the boundary icons. `pdc6`: `[` returns to app.ts and F7 puts it on
Changes 2 / 2.

**Viewed marks across a restart and a push.** The marks the P-C run left were
still there when this session's fresh build opened the Files tab — `pd51`
reads "2/4 viewed" with `one.txt` and `app.ts` ticked — so they survive a cold
restart. Iterations 8 and 9 (the two retargets) touch no file, and `pd53`
confirms the ticks stand at iteration 9. The new spike
`w41_push_to_8401.py` then pushed one line onto `/spike/w39/one.txt`, creating
**iteration 10 · reason `push`**. `pd82` (after the fix below) shows iteration
10 with **1/4 viewed**: `one.txt`'s tick is gone and `app.ts`, which the commit
did not touch, keeps its own. That is R8 end to end.

The marks are per device by design (R8: local, no server-side viewed state) —
the iPad's own Files tab shows a different 2 of 4 (`pdb7`).

> **Defect 1 (fixed): a newer iteration picked from the picker did not clear
> its marks.** `pd80`: at iteration 10, `one.txt` was still ticked even though
> the tenth iteration had just rewritten it. `ViewedFilesStore.prune` was only
> ever called from `PullRequestDetailPage._load`, and `_load` keeps whichever
> iteration the reader had chosen; `_selectIteration` re-read the changes for
> the newly picked iteration and never pruned against them, so stepping the
> picker forward was the one way to meet a version you had not read and keep
> the tick. `_selectIteration` now prunes and refreshes the marks with the
> changes it just read. Test: *"stepping the picker to a newer iteration prunes
> the mark"* in `pr_files_viewed_test.dart`, which needed `PrAdapter` to be
> able to answer a different change list per iteration.

### 6. Comment tools and the Comments tab — pass, P-C's open item closed

Everything R9/R10 asks for renders on 8401's `app.ts` (`pd54`, `pd55`): the
**file-level** thread above the first hunk, the **left-side** thread under
removed line 5, a **deleted** comment as the web's italic "This comment was
deleted" stub with its reply still under it, the **"edited"** marker on the
range thread, the **range** thread itself on lines 12–16, and a **Pending**
status chip. `pd70`–`pd72`: the like button round-trips 1 → 0 → 1 → 0 → 1 with
the icon filling and emptying; the likers' names are a `Tooltip`, which the tap
harness cannot raise, so they are covered by test rather than by screenshot.
`pd72`/`pd73`: the per-comment menu offers **Edit** and **Delete**, and Edit
opens in place with Cancel / Save.

`pd98`: the **Activity** chip lists this walkthrough's own system events in
order — published, marked as draft, published, changed the target branch, set
auto-complete, cancelled auto-complete — each with its kind icon, with the
default staying comments-only.

> **P-C's open item, closed.** The Comments tab's file header
> (`app.ts`, `app.ts:5`, `app.ts:7` — `pd68`) opened the diff at the top of the
> file: `PullRequestDetailPage._openThread` called `_openDiff(path)` and
> `_openDiff` only ever sent `path` and `iteration`, even though the route and
> `PrFileDiffPage` had supported `?line=` since P-C. `_openDiff` now takes an
> optional `line` and `_openThread` passes the thread's own `rightLine`
> (a left-side-only thread has no new-side line, so it opens plain). `pd69`
> shows a tap on `app.ts:7` landing on line 7 with the thread near the top of
> the viewport.

> **Defect 2 (fixed): the pill sat over a thread's own Cancel / Save row.**
> `showsPill` tested only the page's `_composer` — the new-thread box — so a
> thread card's inline **reply** box and its **edit-in-place** field, which are
> the card's own state, left the pill floating over their button row (`pd73`,
> `pd75`). The page now also hides the pill while any text field inside the
> diff has focus, through a `Focus` wrapper around the scrolling content whose
> `onFocusChange` reports descendant focus. `pd76` shows it gone the moment the
> field takes the caret. Test: *"it hides while a thread's own reply box has
> focus"* in `diff_nav_test.dart`.

> **Defect 3 (fixed, and it predates P-D): the reply and edit boxes came up
> unfocused.** Chasing defect 2 turned up that `autofocus: true` on both
> `MentionField`s in `ThreadCard` never actually landed — a probe on the widget
> tree showed `autofocus=true, hasFocus=false` with `primaryFocus` null, on the
> tree with *and* without the change above, so it is P-C's, not mine. The cause
> is the reveal: `_startReply` schedules a `Scrollable.ensureVisible` in the
> same frame the enclosing scope resolves its pending autofocuses, and the box
> came up with no caret and no keyboard — every reply and every edit needed a
> **second tap** before it could be typed into. `_startReply` and `_startEdit`
> now claim the focus in a post-frame callback. `pdf2` shows one tap on Reply
> raising the keyboard with the caret in the field (and, with both fixes
> together, the pill correctly gone). Test: *"the reply box and the edit box
> come up already focused"* in `thread_card_edit_delete_like_test.dart`.

### 7. Inbox — pass; the reviewer reason labels not demonstrable

`pd12`: while auto-complete was set, 8401's row in **Created by me** carried
the **Auto-complete** badge beside the branch line, with **Author** as its
reason label. `pd19`/`pd20`: after Mark as draft the same row shows **Draft**
instead — though only after a pull-to-refresh, because the list is cache-first
and a write on the detail page does not invalidate it (the project's
no-refresh-buttons rule, working as designed, but worth knowing). A real client
PR shows the Draft badge too (`pda7`).

**Not demonstrable:** the *required reviewer* and *optional reviewer* reason
labels. Kelly created every scratch pull request, and the author reason wins,
so all three scratch rows read "Author" whichever filter they are under.

### 8. Devices, themes, type size, landscape, performance — pass

- **Both simulators, both themes.** iPhone dark: `pd91` Overview, `pd92` diff.
  iPad dark: `pde0` Overview, `pde1` side-by-side diff. Light throughout the
  rest of the run. Both apps had their Appearance pinned (the iPhone to Match
  system, which the simulator override did not reach because it was already
  light; the iPad to Light); both were switched and put back.
- **xxxL.** iPhone `pd99`/`pda0`: the three tabs compress to fit, the activity
  rows and the merge-box titles wrap, the filter chips scroll, nothing
  overflows. iPad `pde2`: the same in side-by-side — the thread cards grow and
  the code stays monospace, which is right for a diff.
- **The iPhone in landscape.** `pd93`–`pd97`: all three PR pages — Overview,
  Files and Comments — keep a gutter clear of the Dynamic Island on the left
  and of the corner on the right. Landscape also crosses the phone into the
  **expanded** breakpoint, so the nav pair moves into the app bar and the diff
  goes side-by-side on a phone; both read well at that width.
- **The iPad's Overview at expanded width** (P-B could not check it): `pdb6` is
  a two-column layout, description on the left and merge box / labels /
  reviewers / work items on the right, no overflow.
- **Side-by-side performance** on the largest file available — the diff probe's
  `sample.dart`, **3,078 lines, 44 hunks**, which is far bigger than anything
  in the scratch repo (`pdd4`, `pdd5`, iPad, side-by-side, wrap on):

  | | |
  |---|---|
  | diff | **7 ms** |
  | highlight | **452 ms** (async, off the critical path) |
  | rows | **1 ms** |
  | Nav battery — Changes | **44 stops in 5 ms** |
  | Nav battery — Comments | **4 stops in 1 ms** |
  | frames during the battery | 29 frames, 2 janky (6.9 %), build p90 **3.6 ms**, raster p90 **2.3 ms** |
  | worst build frame | **161.8 ms** — the first layout of the two panes, once |

  Navigation itself is free: jumping through all 44 change stops costs 5 ms in
  total. The only real cost is the first paint of the side-by-side panes and
  the async highlight, neither of which the arrows touch.

---

## Fixes made in this phase

| # | Fix | Files | Test |
|---|---|---|---|
| — | Comments-tab jump passes `&line=` (P-C's open item) | `pull_request_detail_page.dart` | covered on device; `?line=` itself already tested |
| 1 | `_selectIteration` prunes viewed marks against the iteration it just read | `pull_request_detail_page.dart` | `pr_files_viewed_test.dart` (+ `PrAdapter` gained per-iteration changes) |
| 2 | The pill hides while any editor inside the diff has focus, not only the page's own composer | `pr_file_diff_page.dart` | `diff_nav_test.dart` |
| 3 | The reply and edit boxes claim focus post-frame, so one tap is enough | `thread_card.dart` | `thread_card_edit_delete_like_test.dart` |

## New spikes

- **`w41_push_to_8401.py`** (scratch write) — one commit onto PR 8401's own
  source branch to move the iteration, so the viewed marks can be watched
  clearing. Asserts the PR is in the scratch project before writing anything.
- **`s66_required_reviewer_policies.py`** (read-only) — where a *Required
  reviewers* policy exists in the organization, and which active pull requests
  target its branches.

## Still open

- **Not demonstrable on this tenant, and they will stay that way until there is
  a second identity:** the Complete state after a second reviewer's approval;
  reset vote, flag for attention and decline from the app (w39 proved all three
  against the API); the *required reviewer* / *optional reviewer* inbox reason
  labels; and the bypass-refusal text, since the account may bypass.
- **The conflicts list** is still unseen in the app: 8401 merges cleanly and
  w39's deliberate conflict PR was abandoned. The rendering is covered by
  `pr_merge_box_test.dart` only.
- **The branch picker offers the pull request's own source branch** as a
  retarget target, and picking it surfaces the service's raw
  `GitPullRequestRetargetSourceSameAsTarget` as the error text. Excluding the
  source branch from that one list would be a small, obvious follow-up.
- **The Files tab keeps the iteration the reader chose** across a reload, so
  after a retarget or a push the header reads "Iteration 9 of 10" until the
  picker is stepped. The header is honest about it, and the marks now prune
  when it is stepped, but landing on the newest iteration after a *new* one
  arrives may read better.
- **The inbox list does not re-read after a detail-page write** — pull-to-refresh
  picks it up. Consistent with the project's no-refresh-buttons rule.
- **Side by side is offered on a phone**, where R16 only promises it at the
  expanded breakpoint. It defaults off there and on at expanded, so this is an
  override rather than a bug, but it is a menu item that does something
  cramped on a 402 dp screen.
- **`tool/shot-ios.sh` still double-rotates landscape thumbnails** on this iOS,
  as it has since the dashboards walkthrough; the raw `.png` is correct and the
  landscape shots here were read from it.
- Likers' names are a `Tooltip` and cannot be raised by the idb tap harness.
- Android is untested on this Mac: its debug redirect URI is not on the app
  registration.
