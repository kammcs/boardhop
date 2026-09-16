# 22. Pull requests, second pass: completion, reviewers, comment tools, diff navigation

Planned with Kelly on 2026-09-16 after three research passes: the Azure DevOps PR features the app
lacks, mapped against the REST 7.1 reference and verified with spikes s64/s65 (read-only) and
w39/w40 (scratch writes); the app-side inventory of `lib/features/pull_requests/` with the
diff-navigation feasibility; and a survey of GitHub Mobile's PR handling. Kelly's own asks were
**auto-complete on merge** and a user's request for **up/down arrows to move between changes** in a
diff. Decisions here; state in NEXT-STEPS item 29. NEXT-STEPS item 8 records the first pass.

## 1. What the service does (verified 2026-09-16 unless marked Doc)

All calls `api-version=7.1`, base `…/_apis/git/repositories/{repoId}/pullRequests/{id}`.

- **Auto-complete.** `PATCH {autoCompleteSetBy: {id: me}, completionOptions: {mergeStrategy,
  deleteSourceBranch, transitionWorkItems, mergeCommitMessage, autoCompleteIgnoreConfigIds,
  bypassPolicy, bypassReason}}`; cancel with `autoCompleteSetBy: {id: "00000000-0000-0000-0000-000000000000"}`.
  On read: `autoCompleteSetBy` (IdentityRef) and `completionOptions` only when set; the options
  **survive a cancel** (remembered choices); abandon clears it. The service accepts auto-complete on
  a PR with conflicts and, on a target without a blocking policy, merges at once, so the app
  offers it only when `git/policy/configurations?repositoryId=&refName={target}` has a blocking
  policy (the web rule). System thread `AutoCompleteUpdate` (`CodeReviewAutoCompleteNowSet` 1/0).
- **Merge strategies allowed** come from the same policy read: type `fa4e907d-c16b-4a4c-9dfa-4916e5d171ab`
  ("Require a merge strategy"), `settings.allowSquash/allowNoFastForward/allowRebase/allowRebaseMerge`
  (absent = false). A forbidden strategy is still accepted by `PATCH` and the evaluation flips to
  `rejected`, so filter client-side. Minimum reviewers `fa4e907d-…-4906e5d171dd` and required
  reviewers `fd2167ab-…` (`requiredReviewerIds[]`, `isBlocking`) come from the same list.
- **Completion:** `status: completed` with `lastMergeSourceCommit` and the full `completionOptions`
  (`transitionWorkItems` verified; `bypassPolicy`/`bypassReason`, `rebase`, `rebaseMerge` Doc only,
  rebase refused when the target policy forbids it).
- **Draft:** `PATCH {isDraft: true|false}` works both ways (undocumented as patchable); marking
  as draft clears votes on the web; thread `IsDraftUpdate`. **Title/description** `PATCH`.
  **Retarget** `PATCH {targetRefName}` adds an iteration `reason: retarget` with old/new target
  and no files (`$compareTo` previous = empty) and re-queues the merge. **Restart merge** =
  `PATCH {mergeOptions: {detectRenameFalsePositives: false, disableRenames: false,
  conflictAuthorshipCommits: false}}` (`queued` → `succeeded`; stays `conflicts` on a conflict).
- **Merge state:** `mergeStatus` `succeeded|conflicts|queued|rejectedByPolicy|failure|notSet`,
  `mergeFailureType/Message`, `hasMultipleMergeBases` only when set. **Conflicts:**
  `GET {base}/conflicts?excludeResolved=&$top=` (undocumented, 7.1) → `conflictType`
  (`editEdit|editDelete|addAdd|…`), `conflictPath`, base/source/target blob refs, `resolution: {}`;
  `PATCH conflicts/{id} {resolution: {mergeType: takeSourceContent}, resolutionStatus: resolved}`
  verified for editEdit (resolution stays out of v1).
- **Reviewers:** `PUT reviewers/{identityId} {id, vote: 0, isRequired}` adds or toggles required
  (absent = optional); `DELETE reviewers/{id}`; teams as reviewers (`isContainer: true`, member votes
  roll up with `votedFor`); `PATCH reviewers/{id} {isFlagged}` / `{hasDeclined}` (the creator cannot
  decline: 500); reset votes `PATCH reviewers [{id, vote: 0}]` → 204. No vote-on-behalf.
- **Comments:** `PATCH threads/{t}/comments/{c} {content}` moves `lastContentUpdatedDate`;
  `DELETE` leaves `isDeleted: true, content: null` (thread `isDeleted` when none left); **likes**
  `POST/DELETE threads/{t}/comments/{c}/likes` (idempotent), `GET` → `{count, value: [IdentityRef]}`,
  `usersLiked[]` on every read. Threads with `threadContext: {filePath}` only are **file-level**;
  `leftFileStart/End` anchor the **left** (original) side; multi-line = `rightFileStart.line ≠
  rightFileEnd.line` (offset `2147483647` = end of line); `status: pending` exists. Threads read with
  `$iteration=n&$baseIteration=m` move to the left side when the line lives in the base;
  `changeTrackingId` is stable across iterations.
- **System threads** (`commentType: system`, keyed on `properties.CodeReviewThreadType`):
  `VoteUpdate`, `ReviewersUpdate`, `StatusUpdate`, `RefUpdate`, `AutoCompleteUpdate`,
  `IsDraftUpdate`, `TargetChanged`, `ResetMultipleVotes`, `PolicyStatusUpdate`; actor in
  `identities["1"]`, `content` pre-rendered with `{n}` placeholders. 44 of 44 recent client threads
  were system threads.
- **Labels:** `GET/POST/DELETE {base}/labels[/{nameOrId}]` body `{name}`; `labels[]` is filled on
  every **list** route and **never on `GET pullRequests/{id}`**; labels share the project's `wit/tags`.
- **Work item link/unlink** is a work item write: json-patch `add /relations/-` `{rel: ArtifactLink,
  url: vstfs:///Git/PullRequestId/{projectId}%2F{repoId}%2F{prId}, attributes: {name: "Pull Request"}}`;
  unlink = `remove /relations/{index}` after `GET …?$expand=relations`. The service stores `%2f`;
  a plain `/` url is accepted as a duplicate, so write `%2F` and match case-insensitively.
  `POST pullRequests/{id}/workitems` is 405.
- **Share:** `POST {base}/share {receivers: [{id}], message}` → 200. **Commits:** `{base}/commits`
  (continuation header). **Iterations:** `includeCommits=true`, `reason` push/forcePush/create/
  rebase/retarget/resolveConflicts; changes page with `$top/$skip` (`nextSkip/nextTop`).
- **No server-side "viewed file" state** (settings entries and the web data provider have none).
  **No documented hunk-navigation shortcut** on the web (only Ctrl+Alt+S/W for discussions).
- **Scopes:** reads `vso.code`; PR PATCH, reviewers, threads, likes, labels, share `vso.code_write`;
  the work item link `vso.work_write`; cherry-pick/revert `vso.code_manage` (out of v1).
- **Scratch test data:** PR **8401** (active, auto-complete cancelled with `noFastForward`
  remembered, target `refs/heads/scratch/policy-target` which carries blocking policies **192**
  min reviewers = 1 and **193** merge strategy squash + noFF, label `boardhop-spike`, linked to
  #15545, file threads 42973 file-level, 42974 left side, 42976 pending, 42977 on
  `/spike/w39/one.txt`, two statuses). Main and PR 8334 untouched. Tags `boardhop-spike`,
  `boardhop-spike-2` in the pool.
- **Unverified:** full conflict resolution, bypass/rebase completions, share e-mail delivery,
  `vso.code_manage` in the app's token, required-reviewer policy rendering with a real policy.

## 2. Best practice (survey)

GitHub Mobile navigates by **file** (Jump To sheet) and by comment link; **no product ships
prev/next hunk on a phone**, so the ▲▼ control is Boardhop's to own (Azure DevOps web has ▲▼
change and comment pairs; GitLab web `n/p` threads, `]/[` files; VS Code F7 stops at the file
boundary and users asked for continuation). GitHub's auto-merge shows Enable only while the PR is
blocked and offers one-tap disable from the merge box; that maps directly onto Set/Cancel
auto-complete. Its long-open gaps are worth shipping rather than copying: mark as draft,
re-request review, side-by-side on tablets, line wrapping (its top diff request). Viewed files are
server-side there with a "changed since last view" reset; Azure DevOps has none, so a local store
keyed by iteration is the equivalent. Batched pending reviews have no Azure DevOps counterpart.

The app side: `DiffView`'s `_rows` is a flat indexed list feeding a `SuperListView` whose
`ListController` is created but never used for jumps; `visibleRange` exists in super_sliver_list
0.4.1; the code view and diff probe already jump by index. Hunk starts are only counted today,
thread rows are not indexed, left-side-only threads never render, the diff highlights both sides
on the UI thread, and none of the three PR pages wraps `SafeArea(top:false, bottom:false)`.

## 3. Decisions (Kelly, 2026-09-16)

| # | Decision |
|---|---|
| R1 | **Scope:** completion; reviewers, labels and work items; comment tools and diff navigation. **Out:** create PR, cherry-pick/revert, a commits tab, batched review submission (later passes). |
| R2 | **Merge box:** one status block on the Overview (policies, required reviewers, conflicts, linked-item rule); a state-driven primary button: **Complete** when everything passes, **Set auto-complete** while anything waits (hidden when the target has no blocking policy), **Publish** for drafts, **Reactivate** for abandoned; overflow: Mark as draft, Abandon, Change target branch, Restart merge, Share. A banner "Auto-complete set by X · waiting on …" with one-tap **Cancel auto-complete**. |
| R3 | **Completion sheet, shared by Complete and Set auto-complete:** merge type limited to the target policy's allowed strategies (merge, squash, rebase, semi-linear), delete source branch, complete linked work items, custom merge commit message, bypass policies with a reason when the user may, and for auto-complete a "wait for optional policies too" toggle. |
| R4 | **Mark as draft** confirms with the votes-will-be-reset warning; Publish does not. |
| R5 | **Diff navigation:** ▲▼ with three modes, **Changes** (hunks), **Comments** (threads, unresolved first) and **Files**, chosen on the control. |
| R6 | **Placement:** a floating pill, bottom trailing over the diff (above the composer and the safe area) with ▲ ▼ and an "n / m" indicator; hides while composing and on scroll-down, returns on scroll-up; tablets move the pair into the app bar. |
| R7 | **File ends:** no silent wrap. At the last change ▼ shows "Next file: name" and one more tap opens it at its first change; at the last file it reads "Back to files". Symmetric at the top. |
| R8 | **Viewed marks:** local per account and PR, keyed by path with the iteration seen; a later iteration that touches the file clears the mark; a check on the Files tab and in the diff app bar; "viewed/total" in the Files header. |
| R9 | **Comment tools:** edit and delete own comments (per-comment menu, "edited" marker, deleted stub as the web); likes with count and names; file-level comments ("Comment on file" in the diff app bar, rendered above the first hunk) and left-side comments (the gutter on removed lines; existing left-side threads render). Pending status and extra thread filters stay out. |
| R10 | **Multi-line ranges now:** long-press a gutter line then drag to extend; posts a start/end range on the chosen side. |
| R11 | **Activity:** an "Activity" chip on the Comments tab reveals system threads as quiet rows in the timeline; the default stays comments only. |
| R12 | **Reviewers, full set:** add people or teams (existing people search), remove, required/optional toggle, reset a reviewer's vote (author), flag for attention and decline (reviewer; not the creator), required-reviewer names in Checks. |
| R13 | **Inbox rows:** an auto-complete badge and a reason label (required reviewer, optional reviewer, author, draft). Labels chips, comment counts and reviewer avatars stay out. |
| R14 | **Labels editor:** free text with suggestions from the project's tag pool; chips with × to remove. |
| R15 | **Batched review:** later. Comments post immediately; the vote menu stays separate. |
| R16 | **Diff extras:** a line-wrap toggle remembered per account; hardware keyboard shortcuts on iPad and Android (`]`/`[` files, `n`/`p` comments, F7/Shift+F7 changes, `v` viewed); **side-by-side at the expanded breakpoint**. |

## 4. Design

### 4.1 Data (P-A)

- `PullRequest` gains `autoCompleteSetBy`, `completionOptions` (`PrCompletionOptions`),
  `mergeFailureType/Message`, `hasMultipleMergeBases`, `labels`, `closedBy`, `webUrl`; `isDraft` in
  `props`. `PrReviewer` gains `isRequired`, `isFlagged`, `hasDeclined`, `isContainer`, `votedFor`.
  `PrComment` gains `isDeleted`, `lastContentUpdatedDate`, `usersLiked`; `PrThread` gains
  `leftLine/leftLineEnd`, `rightLineEnd`, `isFileLevel`, `systemKind`/`systemText` (system threads
  kept behind a flag instead of dropped). New `PrConflict`, `PrPolicy` (merge strategies allowed,
  min reviewers, required reviewer ids, blocking), `MergeStrategy` enum.
- `PullRequestRepository`: `setAutoComplete(org, pr, options)`, `cancelAutoComplete`, `complete`
  with the full options, `setDraft`, `retarget`, `restartMerge`, `update(title, description)`,
  `addReviewer`/`removeReviewer`/`setRequired`/`resetVote`/`flag`/`decline`, `labels`/`addLabel`/
  `removeLabel`, `editComment`/`deleteComment`, `like`/`unlike`, `conflicts`, `share`, `policies(org,
  project, repoId, targetRef)` (cached, `git/policy/configurations`), `threadBody` with file-level,
  left-side and range contexts; `WorkItemFormRepository`/`WorkItemRepository.linkPullRequest`/
  `unlinkPullRequest` (relations json-patch with `%2F`). `ProjectRepository.tags(org, project)` for
  label suggestions if absent. `ViewedFilesStore` (drift or prefs): `(account, org, prId, path) →
  {iterationId, objectId}`; `DiffPrefs.wrap`.
- Every write online-only (no `WriteQueue` kind); `AdoAuthException` → `AuthInteractionRequired`.

### 4.2 Detail actions (P-B)

- Overview merge box per R2/R3 (`completion_sheet.dart`, `merge_box.dart`, `auto_complete_banner.dart`);
  the More menu per R2; draft confirm per R4; retarget through a branch picker over
  `RepoRepository.branches`; reviewers section actions per R12 with the people picker over
  `PeopleRepository.searchPeople` + `resolveIdentityId` and teams from `SprintRepository.teams`;
  labels chips + editor per R14; work items section +/× with the `#` picker; conflicts list under the
  merge state row; Share through `share_plus` with the web URL; inbox tile per R13
  (`PullRequestTile` badge and reason line).
- Checks: required-reviewer names from the policy read (closes the NEXT-STEPS 8 open item).

### 4.3 Diff navigation and comment tools (P-C)

- `diff_model.dart`: `hunkStarts` (row indices) alongside the count; `diff_view.dart`: thread-row
  and hunk-start indices rebuilt with `_rows`, a `DiffCursor` (mode, position, stops) driven by
  `ListController.animateToItem(alignment: 0.2)` and `visibleRange`; the pill per R6 (`diff_nav_pill.dart`);
  file order from the detail's `changes` for R7 (`_path` becomes state, reload in place);
  `SafeArea(top:false, bottom:false)` on all three PR pages; highlighting through
  `highlightLinesAsync`; left-side rows keyed by `oldNo` so left-only threads render (R9); the gutter
  on removed lines posts left-side; long-press + drag range selection (R10) with a range highlight;
  "Comment on file" action; `ThreadCard` per-comment menu (edit in place with `MentionField`, delete
  confirm), like button with count (R9); Files tab viewed checks and header (R8); wrap toggle and
  the shortcuts (R16) through `Shortcuts`/`Actions` on the diff page; side-by-side layout at the
  expanded breakpoint (two synced panes from the same rows; the composer and threads under the
  right pane, left-side threads under the left).
- Comments tab: the Activity chip (R11) rendering system threads as quiet rows.

### 4.4 Routes and probes

No new routes; the diff route keeps `?path=&iteration=` and gains `?line=` for jumps from the
Comments tab. `/diagnostics/diff` gains a navigation battery (jump timings after the row change,
the pill on `SampleDiff`) and a canned side-by-side.

## 5. Acceptance (scratch PR 8401 and 8334 only for writes)

1. PR 8401: Set auto-complete (squash, delete branch, transition work items, message) reads back
   with the banner; Cancel clears it and the options are remembered in the sheet; the merge-type
   menu offers squash and merge only (policy 193); the button reads Complete only after a second
   reviewer's vote satisfies policy 192 (not demonstrable alone: record).
2. Mark as draft (confirm) and Publish; retarget 8401 to `main` and back (iteration picker labels the
   retarget); Restart merge; edit title.
3. Reviewers: add a team and a person, make required, reset a vote, flag; remove; required-reviewer
   names on a client PR read-only.
4. Labels add/remove; work item link/unlink #15545 (one relation, `%2F`); Share to Kelly.
5. Diff on 8401 and 8334: the pill steps hunks, comments and files with the indicator; Next file at
   the end; Back to files at the last; keyboard shortcuts on the iPad; wrap toggle; side-by-side on
   the iPad; viewed marks survive a restart and clear after a new push (push a commit to 8401's
   source with a spike).
6. Comments: edit, delete (stub), like/unlike, file-level thread, left-side thread on a removed
   line, a multi-line range; the Activity chip lists the day's system events.
7. Inbox: the auto-complete badge on 8401 while set; reason labels.
8. Both simulators, both themes, xxxL, landscape (side insets); Android untested on this Mac;
   walkthrough under `research/walkthroughs/`.

## 6. Out of v1

Create PR from the inbox, cherry-pick/revert, commits tab, batched review submission, pending
thread status and extra thread filters, conflict resolution, view merge changes, follow,
labels/avatars/counts on inbox rows, PR writes through the offline queue.

## 7. What landed (2026-09-16)

Built in dispatcher mode over four phases on `main`, all of it in one day.
Every scratch write went to PR **8401** (`spike/w39-20260916-043401-a` →
`scratch/policy-target`, policies 192 minimum-reviewers and 193 merge-strategy,
both created by w39) or to **8334**; the client projects were read only.

**P-A — the data layer.** `PullRequest` gained `autoCompleteSetBy`,
`completionOptions` (`PrCompletionOptions`), `mergeFailureType/Message`,
`hasMultipleMergeBases`, `labels`, `closedBy`, `webUrl` and `isDraft`;
`PrReviewer` gained `isRequired`, `isFlagged`, `hasDeclined`, `isContainer` and
`votedFor`; `PrComment` gained `isDeleted`, `lastContentUpdatedDate` and
`usersLiked`; `PrThread` gained `leftLine/leftLineEnd`, `rightLineEnd`,
`isFileLevel` and `systemKind`/`systemText` behind a flag. New `PrConflict`,
`PrPolicy`, `PrPolicySet` and `MergeStrategy`. `PullRequestRepository` gained
the whole write set of R2–R14 plus `policies` (cached, `git/policy/
configurations`), `conflicts` and a `threadBody` that can anchor file-level,
left-side and range contexts. `ViewedFilesStore` keeps R8's marks as one JSON
document per pull request in the account-namespaced `JsonCache` rather than a
drift table; `DiffPrefs` keeps wrap and side-by-side. `diff_model.dart` gained
`hunkStarts`. Every write is online-only.

**P-B — the detail actions.** The Overview's merge box (policies required-first
with resolved required-reviewer names, merge state with the conflicts list, the
state-driven Complete / Set auto-complete / Publish / Reactivate button), the
auto-complete banner with Cancel, the completion sheet shared by Complete and
auto-complete, the More menu (Mark as draft with R4's confirm, Publish, Abandon,
Reactivate, Change target branch, Restart merge, Share, Copy link, Edit), the
reviewers section with people and teams, the labels editor over the project's
tag pool, work item link and unlink through the `#` picker, and the inbox tile's
auto-complete badge and reason line. 54 new tests.

**P-C — diff navigation and comment tools.** `DiffCursor` with Changes /
Comments / Files modes, R7's Next file / Back to files at the ends, the floating
pill on phones and the app-bar pair on tablets, the R16 hardware shortcuts that
stay disabled while a field has focus, the viewed check in the diff app bar,
wrap and side-by-side remembered per account, left-side threads rendered and
posted from removed lines, Comment on file, long-press-drag range selection,
`ThreadCard` edit in place and delete with the web's stub, likes with names,
async highlighting over 20k chars, `?line=` on the diff route, and the diff
probe's navigation battery. 56 new tests.

**P-D — acceptance.** The full §5 list on the iPhone 17 and iPad Pro 13-inch
simulators (debug, both themes, xxxL, the phone in landscape), written up in
`research/walkthroughs/2026-09-16-pull-requests.md`. Suite **1824 green**,
`flutter analyze` clean, no exception, overflow or assert on either console.

### Proven on scratch

Auto-complete set, read back in the banner and cancelled, with the options
remembered afterwards and the merge-type list limited to squash and
no-fast-forward by policy 193; the "wait for optional policies too" toggle
correctly disabled because both policies are blocking. Mark as draft with the
vote-reset confirm, and Publish. Retarget to `main` and back, with the iteration
picker labelling every iteration `push` or `retarget`. Restart merge. Title
edited and restored. The project team added as a reviewer, made required, made
optional and removed. A label added and removed against the project's tag pool.
#15545 unlinked and relinked. Share to the system sheet. On the diff: the pill
stepping hunks, comments and files with its indicator, R7's Next file and Back
to files, the mode menu, hiding on scroll-down and while composing, wrap, the
viewed check; on the iPad the app-bar pair, side-by-side with left-side threads
under the left pane, and all four keyboard shortcut families. Viewed marks
survived a cold restart and then cleared for exactly the file a new commit
touched — `w41_push_to_8401.py` pushed one line onto `/spike/w39/one.txt`,
making iteration 10. Comment edit, delete stub, like and unlike, file-level,
left-side, range and pending threads, and the Activity chip listing the run's
own system events. The inbox's auto-complete and Draft badges.

Read-only on a client project, `s66_required_reviewer_policies.py` found the
five *Required reviewers* policies in the organization (the scratch branch has
none) and one of their pull requests was opened to confirm the merge box
renders **Required by policy** with all six names resolved — which closes
NEXT-STEPS item 8's last open note.

### Device defects fixed in P-D

1. **The Comments tab never sent `&line=`.** The route and the diff page had
   supported it since P-C, but `_openDiff` only ever passed `path` and
   `iteration`, so a tap on a thread's file header opened at the top of the
   file. It now carries the thread's own `rightLine`.
2. **A newer iteration picked from the picker did not clear its viewed marks.**
   `ViewedFilesStore.prune` ran only from `_load`, which keeps whichever
   iteration the reader chose, so stepping the picker forward was the one way
   to meet an unread version and keep the tick. `_selectIteration` prunes now.
3. **The nav pill sat over a thread's Cancel / Save row.** `showsPill` tested
   only the page's own new-thread composer; a card's inline reply box and its
   edit-in-place field are the card's state. The pill now also hides while any
   field inside the diff has focus.
4. **The reply and edit boxes came up unfocused** (a P-C defect found while
   chasing 3): `autofocus: true` lost the race with the `ensureVisible` that
   reveals the composer, so both needed a second tap before they could be typed
   into. `_startReply` and `_startEdit` claim the focus post-frame.

### Still open

Not demonstrable while Kelly is the only identity on the tenant: the Complete
state after a second reviewer's vote; reset vote, flag and decline driven from
the app (w39 proved all three against the API); the required/optional reviewer
inbox reason labels; and the bypass-refusal text. The conflicts list has still
never been seen in the app, because 8401 merges cleanly and w39's conflict PR
was abandoned. Smaller: the branch picker offers the pull request's own source
branch and shows the service's raw refusal code; the Files tab keeps the
reader's chosen iteration after a new one arrives; the inbox list needs a pull
to pick up a detail-page write; Side by side is offered on a phone, where R16
only promises it at the expanded breakpoint; likers' names are a tooltip the
tap harness cannot raise; and `tool/shot-ios.sh` still double-rotates landscape
thumbnails on this iOS.
