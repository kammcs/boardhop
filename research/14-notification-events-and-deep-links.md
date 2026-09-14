# 14. Notification events, audiences and deep links (relay R2)

**Date:** 2026-09-13 (Kelly interviewed the same day; decisions in §8)
**Scope:** how one Azure DevOps service-hook post becomes zero or more push notifications, what each notification says, whom it reaches, what the phone does when it arrives and when it is tapped. This is the design for relay phase **R2** (routing) and the app work that goes with it. The two tiers, the pointer contract and the "ingest All, keep metadata, enrich on the device" decision are in `research/06-notification-relay-and-extension.md` and are not reopened here.
**Numbering:** `research/13` is the iOS walkthrough plan, so this is 14.

## 0. Ground rules carried over from research/06

- Hooks send `resourceDetailsToSend: all`. The relay reads the body **in memory**, computes actor, audience and pointer, and persists nothing from the body. The only durable trace of an event is the routing log (event type, artifact ids, subscription id, device ids, outcome) and the small per-artifact state in §5.
- What leaves the relay is a `PushPointer`: `org, eventType, artifactType, artifactId, project, title(≤80), deepLink` **plus (new in R2) `actor`, `verb`, `subId`** (§3.2). Titles are metadata; comment bodies, descriptions, field values and diffs are content and never transit the gateway.
- The device enriches before display with the user's own token and falls back to the pointer line.
- The relay knows a device only as `(org, userId, userDescriptor, platform, token)`. Audience computation therefore produces **identity ids**, and a notification is sent to every registered device whose `(org, userId)` matches.

## 1. Event families and subscriptions

Nine subscriptions per project today (spike w22), chosen from the catalogue in `research/spikes/results/s39_hook_publishers.md`. R2 changes the set to the thirteen below (twelve that can notify plus `run-state-changed`, which only feeds relay state). `X-VSS-SubscriptionId` (header) and `subscriptionId` (body) tell the relay which subscription fired, which is how it knows *what kind* of PR update it is looking at without diffing state (§1.2).

| publisher | event id | resourceVersion | filter inputs the relay relies on | in beta? |
|---|---|---|---|---|
| tfs | `git.pullrequest.created` | 1.0 | none | yes |
| tfs | `git.pullrequest.updated` ×4 | 1.0 | `notificationType` = each of the four kinds (§1.2) | yes |
| tfs | `ms.vss-code.git-pullrequest-comment-event` | 2.0 | none | yes |
| tfs | `git.pullrequest.merged` | 1.0 | `mergeResult` = `Unsuccessful` (it fires on every merge attempt otherwise, w24) | yes, author only |
| tfs | `workitem.updated` | **5.1-preview.3** (see §1.1) | `changedFields` empty (any); the relay filters | yes |
| tfs | `workitem.commented` | 5.1-preview.3 | none | subscribed, dropped by the relay (§2.1 note) |
| tfs | `workitem.created` | 5.1-preview.3 | none | yes, only when created assigned to someone else |
| tfs | `build.complete` | 2.0 | none | yes |
| pipelines | `ms.vss-pipelinechecks-events.approval-pending` | 5.1-preview.1 | none | yes |
| pipelines | `ms.vss-pipelines.run-state-changed-event` | 5.1-preview.1 | none | subscribed, never notifies: it is the only event that gives the run's requester as an identity (§1.4) |
| pipelines | `ms.vss-pipelines.stage-state-changed-event` | 5.1-preview.1 | none | later (failed stage before the run ends) |
| pipelines | `ms.vss-pipelinechecks-events.approval-completed` | 5.1-preview.1 | none | yes (replaces the pending notification through the same collapse key) |

Payload facts verified by capture (All + text; w22/w23 on 2026-09-13, then w24/w25 the same day, key trees in `research/spikes/results/w24_r2_capture_shapes.md`, summary in that folder's README): **every event in the table** (Kelly approved the Deploy stage of run 20260913.1 from the app at 15:51Z, which delivered `approval-completed`, the Completed `run-state-changed` and `build.complete` v2). The one shape still unverified is `build.complete.triggerInfo` for a **PR validation build**: it was `{}` for the manual run, and the scratch repo has no build policy to produce a PR build.

### 1.1 The identity of the actor and of each audience member

Every payload names people as identity refs with `id` (the identity GUID the relay stores from `connectionData.authenticatedUser.id`), `displayName`, `uniqueName`, sometimes `descriptor`. The relay matches on **`id`**, never on name or mail. Verified in w22: `revisedBy.id`, `comment.author.id`, `pullRequest.createdBy.id`, `reviewers[].id` are present. Work item identity fields are the trap: at resourceVersion **1.0** and **3.1-preview.3** `System.AssignedTo`, `System.CreatedBy` and `System.ChangedBy` arrive as `"Name <mail>"` **strings** (1.0) or `{displayName, name, uniqueName}` objects **without an id** (3.1-preview.3), in both `revision.fields` and `fields.*.oldValue/newValue`; only **5.1-preview.3** sends full identity refs `{id, descriptor, displayName, uniqueName, …}`. Found on 2026-09-13 when the first live assignment routed with no `assigneeId` (spikes w27/w28); the three work item subscriptions are therefore created at 5.1-preview.3 and the relay's `RoutingView` reads the objects. `revisedBy` carries an `id` at every version.

### 1.2 `git.pullrequest.updated` fires for everything

One event covers reviewer votes, reviewer list changes, status changes (active/abandoned/completed/draft) and new pushes (iterations), and the body has no "what changed" field. Two ways to know the kind: diff against relay-kept state (§5) or **subscribe four times with the `notificationType` filter** the publisher exposes for this event (s39). The second is stateless and self-describing, so R2 does that; the relay maps `subscriptionId → kind`. **Verified (s41, w24):** the values are exactly `PushNotification`, `ReviewersUpdateNotification`, `StatusUpdateNotification`, `ReviewerVoteNotification`; each action fired exactly one filtered subscription, and a retitle fired none of the four. One caveat from w24: **the payload's `resource` is rendered at delivery time**, so a ReviewersUpdate body lists the reviewers as they are a second later, not a before/after; "who was added" is a diff against the relay's `pr_state` (§5.1).

### 1.3 Mentions

- **Work items:** a mention in a comment or in `System.History` arrives as HTML `<a href="#" data-vss-mention="version:2.0,{identityGuid}">@Name</a>`. The relay extracts the GUIDs from `resource.comment.text` (`workitem.commented`) or `fields["System.History"].newValue` (`workitem.updated`) with one regex, keeps the GUIDs, discards the text.
- **Pull request comments:** `comment.content` carries `@<{identityGuid}>`. Same treatment.
- Mentions are the highest-priority audience rule: a mentioned person gets "mentioned you" even if another rule would also have notified them, and one person gets one notification per event (§5.3).

### 1.4 Builds, runs and approvals

`build.complete` (tfs, resource `Build` v2) and `run-state-changed-event` (pipelines) describe the same finish twice; the tfs event carries `requestedFor`, `requestedBy`, `result`, `sourceBranch`, `definition`, `triggerInfo` (verified empty for a manual run; the documented `pr.number` for PR builds is unverified) plus `definition {id, name}`, `project {id, name}`, `sourceBranch` and `reason` (verified, w25), which is exactly what routing needs, so R2 keeps `build.complete` for the finish. **But `run-state-changed` stays subscribed for one reason (w24/w25):** `approval-pending` names the run's requester only as a display-name string (`run.requestedFor: str`), while `run-state-changed` (fired at queue time, a second after the run starts) carries `requestedFor` and `requestedBy` as full identities with `id`. The relay keeps `(org, runId → requestedForId, requestedById, pipelineId)` from it (`run_state`, §5.1) and sends nothing for it. `approval-pending` (verified) carries `approval {id, status, instructions, executionOrder, blockedApprovers[], pipeline {id, name, owner {id = run id, name}}, steps[] {assignedApprover {id, displayName, uniqueName, descriptor}, status, order}}`, `approvalId`, `pipeline {id, name}`, `resource {id, name, resourceType}` (the environment), `run {id, name, requestedFor, runReason}`, `runId`, `stage {id, name}`, `stageName`, `projectId`; its `resourceContainers` has **no `project` entry**, so the project comes from `resource.projectId`. A step whose approver is a **group** (`isContainer`) cannot be expanded by the relay without an identity of its own (Graph); the beta notifies direct-user approvers only and records the gap for the service-principal path (s40).

## 2. Event → notification map

Conventions used in the tables:

- **Audience** lists who is notified; **minus actor** is implied everywhere (§5.2).
- **Verb** is what the app renders after the actor: "Javier Perez *replied on* !8261".
- **Collapse key** is what repeated notifications share so they replace each other in the shade (APNs `apns-collapse-id` and thread id, FCM `tag`, Android `notificationId`). The tables write it without the org for brevity; the relay emits `{org}.{key}` (R2.3), e.g. `contoso.pr.8348.t4821`, so a phone registered for two orgs never collapses two artifacts together, and adds the thread suffix in the comment cases so a comment thread and a state change on the same PR do not eat each other. Android's FCM `collapse_key` is the artifact family only (four per device), the exact key is the notification tag.
- **Route** is the app's account-scoped path; `{acct}` is filled in by `PushPointer.route(accountId)`. "+query" marks a query parameter the router does not read yet (§4).
- **Title** in the pointer is the artifact's title (work item title, PR title, `definition.name · buildNumber`). Nothing else.

### 2.1 Work items (`artifactType: workItem`, `artifactId: {id}`, `project` from `resourceContainers.project` / `revision.fields["System.TeamProject"]`)

| event | condition (from the All body) | audience | verb | collapse key | route | tap |
|---|---|---|---|---|---|---|
| `workitem.updated` | `fields["System.AssignedTo"]` changed and `newValue.id` ≠ actor | new assignee | assigned you | `wi.{id}` | `/projects/{p}/work-items/{id}` | open the work item |
| `workitem.updated` | `System.AssignedTo` changed | previous assignee (`oldValue.id`), if any | reassigned #{id} | `wi.{id}` | same | open the work item |
| `workitem.updated` | `System.State` changed | current assignee; creator (`revision.fields["System.CreatedBy"]`) when they differ from the assignee | moved #{id} to {newState} | `wi.{id}` | same | open the work item |
| `workitem.updated` | `System.History` in `fields` with mentions (a comment written through the History field) | mentioned users | mentioned you | `wi.{id}.comments` | same +`?comment={commentId}` when the body carries one, else no anchor | open, scroll to Discussion |
| `workitem.updated` | any other field, incl. Title, Priority, Iteration, Description, tags, links | **nobody in the beta** (preference `workItems.anyChangeOnMine`, default off, turns on "assignee gets edited #{id}") | edited #{id} | `wi.{id}` | same | open the work item |
| **comment** = `workitem.updated` whose `fields` are the comment-noise set (§5.2 rule 3) | always | assignee; creator when different; mentioned users get "mentioned you" instead | commented on #{id} | `wi.{id}.comments` | same +`?comment={resource.revision.commentVersionRef.commentId}` (verified at v1.0, w24) | open, scroll to Discussion and highlight the comment |
| `workitem.commented` | always | **nobody: dropped** (R2.1 finding, see the note below) | | | | |
| `workitem.created` | `System.AssignedTo` set and ≠ actor | assignee | created #{id} for you | `wi.{id}` | same | open the work item |
| `workitem.created` | otherwise | nobody | | | | |

**Comment actor (R2.1 finding, 2026-09-13):** the `workitem.commented` v1.0 body has no identity object at all — `System.ChangedBy` and `System.CreatedBy` are plain `"Name <mail>"` strings — so the relay cannot tell who commented and would notify the commenter about their own comment. The paired `workitem.updated` post for the same comment carries `revisedBy.id`, `fields["System.History"].newValue` (the mention GUIDs) and `revision.commentVersionRef.commentId`. §5.2 rule 3 is therefore inverted from the first draft: **the comment-noise `workitem.updated` is the comment notification and `workitem.commented` is dropped** (the subscription stays so the health view sees it, and R2.8 may simply not create it).

Notes. State-change audience deliberately excludes "everyone who ever touched it": the web's own default is assignee, creator and followers, and followers are not readable by the relay (Notification API is per user, §research/05 8.2). A work item **without** a team project name in `revision.fields` (should not happen) falls back to `resourceContainers.project.id`; the app's routes take a project **name**, so the relay keeps a `(org, projectId → projectName)` map filled from every payload that carries both (metadata).

### 2.2 Pull requests (`artifactType: pullRequest`, `artifactId: {pullRequestId}`, `project` = `repository.project.name`; the PR route is org-level so the project is informational)

| event | condition | audience | verb | collapse key | route | tap |
|---|---|---|---|---|---|---|
| `git.pullrequest.created` | not a draft (`isDraft` false) | all reviewers (`reviewers[].id`, minus `isContainer` groups) | asked you to review !{id} | `pr.{id}` | `/pull-requests/{id}` | open the PR overview |
| `git.pullrequest.created` | draft | nobody (reviewers are told when it leaves draft, via the status update) | | | | |
| `updated` / ReviewersUpdate | reviewer ids added since the relay's last state for this PR (§5) | the added reviewers | asked you to review !{id} | `pr.{id}` | same | open the PR overview |
| `updated` / ReviewerVote | a reviewer's `vote` ≠ 0 | PR author (`createdBy.id`) | approved / approved with suggestions / waited on / rejected !{id} (from `vote` 10, 5, −5, −10; `0` = vote reset, not notified) | `pr.{id}` | same | open the PR overview |
| `updated` / StatusUpdate | `status` → `completed` or `abandoned`, or `isDraft` true→false | author for completed/abandoned (if actor ≠ author); reviewers when a draft is published ("asked you to review") | completed / abandoned / published !{id} | `pr.{id}` | same | open the PR overview |
| `updated` / Push (new iteration) | `lastMergeSourceCommit` changed | reviewers who have already voted (their vote resets or goes stale) | pushed new changes to !{id} | `pr.{id}` | same +`?tab=files` | open the PR on Files |
| `ms.vss-code.git-pullrequest-comment-event` | comment on a thread | PR author; every other author in the same thread (the v2 body carries `comment` and the whole `pullRequest` but **not the thread** (w24): the thread id is parsed from `comment._links.threads.href`, and participants come from the relay's `pr_thread_state`, which accumulates author ids from every comment event it sees on that thread); reviewers who have voted; mentioned users get "mentioned you" | commented on / replied on !{id} (replied when `parentCommentId` > 0) | `pr.{id}.t{threadId}` | same +`?thread={threadId}` | open the PR on Comments, scroll to the thread; a file thread opens the file diff at the thread (the page already does this from the Comments tab) |
| `git.pullrequest.merged` (subscribed with `mergeResult` = `Unsuccessful`; unfiltered it fires on every successful merge attempt too, twice in w24) | `mergeStatus` conflicts, failure or rejected by policy | author | merge failed on !{id} | `pr.{id}` | same | open the PR overview |

Notes. A **system comment** (`commentType` = system, e.g. "voted", "updated the PR") is ignored in the comment event; votes and pushes are covered by their own update kinds. Group reviewers (`isContainer`) are skipped in the beta (same limitation as approvals). Required-reviewer policy additions arrive as ReviewersUpdate and are handled the same way.

### 2.3 Builds (`artifactType: build`, `artifactId: {build.id}`, `project` = `project.name`)

| event | condition | audience | verb | collapse key | route | tap |
|---|---|---|---|---|---|---|
| `build.complete` | `result` ∈ failed, partiallySucceeded, canceled | `requestedFor.id` (and `requestedBy.id` when different and a person); for a PR validation build (`triggerInfo["pr.number"]` or `reason` = pullRequest) also the PR author (`triggerInfo["pr.sender.name"]` is a name, so the relay resolves the PR author from its §5 PR state when it has one, else notifies `requestedFor` only) | failed / partially succeeded / canceled — {definition.name} {buildNumber} | `build.{id}` | `/projects/{p}/pipelines/runs/{id}` | open the run page |
| `build.complete` | `result` = succeeded | `requestedFor.id` **only when** the definition's previous known result for this branch (§5) was a failure ("fixed"), or when the user has `builds.notifySucceeded` on | succeeded — … | `build.{id}` | same | open the run page |

A scheduled or CI build "requested for" a service identity (`requestedFor.uniqueName` is a build service account) has no person to notify; such an event is logged and dropped. Actor for a build is `requestedBy`; the "not the actor" rule does **not** apply to builds (you want to hear that your own push failed).

### 2.4 Approvals (`artifactType: approval`, `artifactId: {approval.id}`, `project` from `resourceContainers.project`)

| event | condition | audience | verb | collapse key | route | tap |
|---|---|---|---|---|---|---|
| `approval-pending` | steps with `assignedApprover` a user | those approvers, minus the run's requester when they are the same person **unless** they are the only approver (self-approval is common on small teams) | needs your approval — {pipeline.name} → {stage or environment} | `approval.{id}` | `/projects/{p}/pipelines?approval={id}` +query | open the Pipelines page on the Approvals tab with that approval's sheet open (approve / reject with comment, as the tab already does) |
| `approval-completed` | `approval.status` approved or rejected; actor = `steps[].actualApprover.id` (verified, w25); `run.requestedFor` is null here, so the requester comes from `run_state` | the other approvers of the same approval, and the run's requester | approved / rejected … | `approval.{id}` | `/pipelines/runs/{runId}` | replaces the pending notification (same collapse key), opens the run page |

The run page (`/pipelines/runs/{runId}`) is the natural second hop; the approval's `owner.id` is the run id and goes in the pointer as `runId` so the sheet can offer "Open run".

## 3. Pointer additions and the notification text

### 3.1 What the relay puts in the alert (the fallback line, shown when enrichment fails or before it runs)

- **Title (OS heading):** the artifact line: `#15545 · Fix the snackbar` / `!8334 · Boardhop spike PR` / `boardhop-scratch · 20260913.4` / `boardhop-scratch → Deploy`. This is the pointer `title` prefixed with the artifact id, built by the relay from metadata only.
- **Body:** `{actor} {verb}`: "Kelly Kamm assigned you", "Javier Perez replied on !8261", "Build failed — requested by you", "Needs your approval".
- **Subtitle (iOS) / sub-text (Android):** `{project}` (and repository for PRs).

Nothing else. No comment preview. When the actor is a service identity the body is the verb alone.

### 3.2 `PushPointer` in R2

| field | type | notes |
|---|---|---|
| `org`, `eventType`, `artifactType`, `artifactId`, `project`, `title`, `deepLink` | as R1 | `deepLink` is now always set by the relay (org-relative), including query anchors |
| `actor` | string ≤ 60 | display name of who did it; absent for service identities |
| `actorId` | string | identity GUID, so the app can hide a self-caused notification that slipped through and enrichment can compare |
| `verb` | enum string | `assigned`, `reassigned`, `stateChanged`, `edited`, `commented`, `replied`, `mentioned`, `reviewRequested`, `voted`, `prCompleted`, `prAbandoned`, `prPublished`, `pushed`, `mergeFailed`, `buildFailed`, `buildPartial`, `buildCanceled`, `buildSucceeded`, `buildFixed`, `approvalPending`, `approvalCompleted`, `test`. The **app** turns the enum into words (localizable); the relay's fallback line uses English. |
| `detail` | string ≤ 40 | metadata that the verb needs: the new state name, the vote label, the stage name, the build result. Never free text from a comment or description. |
| `anchor` | string | `comment:{id}`, `thread:{id}`, `approval:{id}`, `tab:files`; the same thing the `deepLink` query says, made explicit for the enrichment step |
| `runId` | string | approvals only |
| `subId` | string | the hook subscription id that produced it, for support and for the relay's own health view; never shown |
| `sentAt` | ISO-8601 | so enrichment can ignore a stale pointer (>10 min) and skip fetching |

Field budget: APNs payload cap is 4 KB, FCM 4 KB; the pointer stays well under 1 KB. The compile-time promise in `relay/lib/src/gateway/pointer.dart` still holds: every new field is a short string with a length cap; `detail` is validated against a closed list per verb.

### 3.3 Transport per platform

- **iOS:** alert push, `mutable-content: 1`, `thread-id` = collapse key, `apns-collapse-id` = collapse key, `interruption-level` `active` (approvals `time-sensitive` **if** Kelly wants them to break Focus; needs the entitlement, decide in §8). Category `boardhop.pointer` so the Notification Service Extension is invoked for every pointer.
- **Android:** **data-only** message, `priority: high`, `ttl` 1 h, `collapse_key` = collapse key (FCM allows four collapse keys per device at a time, so the relay uses the artifact family as the FCM `collapse_key` and the exact key only as the notification tag). The app posts the notification itself after enrichment (§4).

## 4. On the device

### 4.1 Enrichment: what is fetched per verb

The rule: one or two GETs with the user's own token, all through calls the app already has, and every fetch is optional.

| verb family | fetch | what changes in the notification |
|---|---|---|
| work item `assigned`, `reassigned`, `stateChanged`, `edited`, `created` | `wit/workitems/{id}` (`WorkItemRepository.refreshItem`) | title refreshed; body gains type and state: "Kelly Kamm assigned you · User Story · Active"; the item is written to the cache so the tap opens instantly, offline included |
| work item `commented`, `replied`, `mentioned` | the work item plus `wit/workItems/{id}/comments?$top=…` (`comments`) and pick `anchor` | body becomes the comment's **plain text**, 2 lines (HTML stripped, mentions rendered as @Name); the notification's large text is the whole comment on Android, `body` on iOS |
| PR `reviewRequested`, `voted`, `prCompleted`, `prAbandoned`, `prPublished`, `pushed`, `mergeFailed` | `git/pullrequests/{id}` (`PullRequestRepository.get`) | title refreshed, body gains repo, source → target branch, and for votes the reviewer's vote label |
| PR `commented`, `replied`, `mentioned` | the PR plus `threads/{threadId}` (`rawThreads`, filtered to the thread) | body = comment plain text; subtitle = `file.js:38` for a file thread |
| `buildFailed` etc. | `build/builds/{id}` (`run`) and the timeline (`timeline`) | body = the first failed task's name and its first issue message, e.g. "Deploy › Run tests: 3 tests failed"; for succeeded, duration |
| `approvalPending` | `pipelines/approvals/{id}?$expand=steps` (via `approvals` filtered) | body = instructions (metadata written by the pipeline author) and the run name |

Budget and behaviour, both platforms:

- **Time budget:** iOS gives an NSE about 30 s; the extension caps its own work at **8 s** and hands back whatever it has. Android's `onMessageReceived` has ~20 s of guaranteed execution at HIGH priority; the service caps at **8 s** and posts the fallback if the fetch is not back.
- **Token:** MSAL `acquireTokenSilent` for the account whose `userId` registered the org (the registrar stores `(accountId, org, userId)`; the pointer carries `org`, `actorId` and the audience is implicit: this device). If silent acquisition needs interaction (CA, expired refresh token) the notification shows the fallback line and the app, when opened next, raises `AuthInteractionRequired` as it does today.
- **Offline / fetch failed / 401 / 404 (artifact deleted or not permitted):** fallback line, still delivered; nothing is retried in the background. A 404 also drops the deep link's anchor.
- **Stale:** `sentAt` older than 10 minutes → no fetch, fallback line.
- **Multiple accounts on one phone:** the device registers once per signed-in account and org; the pointer's `org` is looked up in the registrar table to pick the account. Unknown org → fallback line, tap lands on the org picker.
- **Foreground:** iOS presents remote pushes itself (R1 finding); the app additionally refreshes the page if it is already showing that artifact. Android: the message is data-only, so the app posts it even in the foreground **unless** the artifact is on screen, in which case it refreshes the page and shows a small snackbar instead of a notification.
- **Lock screen:** Android channel `activity` is created with `lockscreenVisibility = PRIVATE` and every enriched notification carries a **public version** that is the fallback line, so a locked phone shows "Javier Perez replied on !8261 · ServiceDelivery" and the comment text appears after unlock. iOS has no per-notification redaction; the system "Show Previews: When Unlocked" setting governs, and the fallback title (artifact id + title) is what shows when previews are hidden. Comment text, build error text and approval instructions are the three things that only appear in the enriched body; the artifact title is metadata and appears in both.
- **Grouping:** iOS `threadIdentifier` = collapse key, so a thread's replies stack under one header; Android uses `setGroup(collapse family)` and a summary notification once there are three or more.
- **Badge (iOS):** the relay does not know the count; the app sets the badge to its own unread count from the local `notified` set when it runs. Off in the beta.

### 4.2 Taps and routes

`PushPointer.route()` today builds the route from the ids and takes a relay `deepLink` only when it already starts with `/a/`. R2 keeps that safety rule (the relay never names an account) and makes the app build **anchors** from `anchor`:

| artifact | route today | R2 addition | router work |
|---|---|---|---|
| work item | `/projects/{p}/work-items/{id}` | `?comment={id}` scrolls to Discussion and highlights the comment for 2 s | `WorkItemDetailPage` takes `initialCommentId`; the Discussion section gets a `GlobalKey` per comment and `Scrollable.ensureVisible` after the comments load |
| pull request | `/pull-requests/{id}` | `?tab=comments|files`, `?thread={id}` selects the tab and scrolls to the thread card; a file thread opens the diff page at the thread the way the Comments tab does | `PullRequestDetailPage` takes `initialTab` and `initialThreadId`; the thread list uses `super_sliver_list`'s `animateToItem` or a key map |
| build | `/pipelines/runs/{id}` | none needed; a failed task is already inline. Later: `?record={id}` to expand the failed job | none in R2 |
| approval | `/pipelines` (falls back to the list today) | `/pipelines?tab=approvals&approval={id}` opens the Approvals tab and the approve/reject sheet for that id; if the approval is no longer pending the tab shows the list and a snackbar "Already decided" | `PipelinesPage` takes `initialTab` and `initialApprovalId` |
| unknown / test | `/activity` | unchanged | |

Cold start: `takeLaunchPointer()` already carries the pointer through sign-in; the deep link opens after the shell is up (verified on Android in R1, on the iPhone in the Mac session).

The Activity feed gets each pushed pointer inserted as an `ActivityItem` at once (kind by artifact, `actor` from the pointer), so the feed and the notifications agree without waiting for the next poll; the poll dedups on `key`. **Amended 2026-09-14:** when the native side posts (Android's messaging service, the iOS extension) Dart is not running, so the pointer is queued on the platform (`PushedQueue` / `push.pending` in the app group) and drained through `drainPushed` at start, on resume and before every poll's notify step; and pushed rows are flagged `pushed` so `refresh` keeps them for seven days instead of replacing the feed with the poll's narrower sources. Without both, the Pixel showed the approval twice (the second with the Pipelines route) and no build row at all.

## 5. Relay-side state, dedup and fan-out

### 5.1 What the relay keeps (metadata only, per org)

| table | columns | why |
|---|---|---|
| `pr_state` | `org, prId, status, isDraft, sourceCommit, reviewers (json: id → vote), authorId, updatedAt` | added-reviewer detection (the payload shows reviewers as of delivery, not before/after), PR author for PR builds |
| `pr_thread_state` | `org, prId, threadId, participantIds (json), updatedAt` | thread participants for the comment audience; filled from every comment event, so threads older than the relay start with the author only |
| `run_state` | `org, runId, pipelineId, requestedForId, requestedById, createdAt` | from `run-state-changed` at queue time; the approval event names the requester only by display name |
| `build_state` | `org, projectId, definitionId, branch, lastResult, buildId` | "fixed" detection |
| `projects` | `org, projectId, projectName` | routes need names, some payloads carry only the id |
| `deliveries` | `org, eventId (X-VSS-ActivityId), subId, artifactKey, userId, sentAt` | idempotency (Azure DevOps retries a hook that answered 5xx) and the 24 h fan-out cap |
| `prefs` | §6 | |

Rows in `pr_state` and `build_state` expire 90 days after their last update. None of these hold a title, a name or text.

### 5.2 Rules

1. **Never the actor.** The actor is `revisedBy.id` / `comment.author.id` / `createdBy.id` for a new PR / the voting reviewer / `requestedBy.id`. Anyone equal to the actor is removed from every audience, with two exceptions: builds (you want your own failed build) and self-approval when you are the only approver.
2. **One notification per person per event.** If several rules select the same person, the highest-priority verb wins: mentioned > assigned/reviewRequested > voted/stateChanged/approval > commented/replied > edited/pushed.
3. **Two hooks for one action.** A work item comment fires `workitem.commented` **and** `workitem.updated`; the updated body's `fields` for a comment are exactly `System.AuthorizedDate, System.ChangedDate, System.CommentCount, System.History, System.Rev, System.RevisedDate, System.Watermark` (w24). The relay treats a `workitem.updated` whose changed fields are a subset of `{System.History, System.CommentCount, System.Rev, System.ChangedDate, System.ChangedBy, System.AuthorizedDate, System.RevisedDate, System.Watermark, System.AuthorizedAs, System.PersonId}` **and include `System.History`** as **the comment event** (actor `revisedBy.id`, comment id from `revision.commentVersionRef`), and drops `workitem.commented`, whose body names nobody by id (§2.1 note). A `workitem.updated` in that set without `System.History` (a bare `System.Rev` bump) is noise and dropped. Likewise the four filtered PR subscriptions mean a retitle produces no post at all, and `git.pullrequest.merged` is filtered to `Unsuccessful` at subscription time. Likewise a vote fires a system comment on the PR comment event; system comments are dropped and the ReviewerVote update notifies.
4. **Retries.** `X-VSS-ActivityId` is unique per delivery attempt of one event; the relay answers `200` fast (within 2 s, work queued in-process) and dedups on `(subId, X-VSS-ActivityId)` for 24 h so a retried delivery sends nothing twice. `X-VSS-SubscriptionId` must match a subscription the relay created for that org (the extension's data store, later; a config file in the beta) or the post is answered 404 and dropped, which is also the answer for a wrong or missing basic-auth secret.
5. **One event, several projects.** Subscriptions are per project, so one action fires once per project it belongs to; nothing to merge. A PR's project and its linked work items' projects are different artifacts and legitimately produce different notifications.
6. **Fan-out cap.** At most 50 recipients per event (a PR with 60 reviewers is a distribution list, not a review) and at most 60 notifications per user per hour per org; the overflow is dropped and counted in the routing log. The gateway's per-device outcome handling (410 / UNREGISTERED delete the row) is unchanged.
7. **Quiet, not lost.** A person with no registered device is simply not a recipient; the relay keeps no inbox. Kelly's requirement is push, not a message store.

### 5.3 Processing order

`receive → auth (basic secret, subscription id) → dedup → parse minimal routing view → drop-noise → compute (actor, candidates by rule) → apply prefs (§6) → dedup per person → build pointer → look up devices → send → log (ids only) → forget the body`. The body is held in one `Map` for the duration of the request and is never written, not even at debug log level (the logger's `redact` list gets `fields`, `comment`, `message`, `detailedMessage`, `description`).

## 6. Per-user preferences

Where: **on the relay, per `(org, userId)`**, not per device, so two phones agree and a reinstall keeps them; the app edits them with the user's own token through `GET/PUT /v1/prefs?org=` (same auth as `/v1/devices`, the relay validates the token once against `connectionData` and matches the user id). The app mirrors them in `shared_preferences` for display when offline. The device row keeps its `tzOffsetMinutes` (sent with the heartbeat) for quiet hours.

| preference | default | values |
|---|---|---|
| `enabled` | true (registration itself is the opt-in) | |
| `workItems.assigned` | on | on / off |
| `workItems.stateChanged` | on | on / off |
| `workItems.comments` | on | on / mentions only / off |
| `workItems.anyChangeOnMine` | **off** | on / off |
| `pullRequests.reviewRequested` | on | |
| `pullRequests.votes` | on | on / rejections and waits only / off |
| `pullRequests.comments` | on | on / mentions only / my threads only / off |
| `pullRequests.completedAbandoned` | on | |
| `pullRequests.pushes` | **off** | |
| `builds` | failuresAndFixed (D3) | failures / failuresAndFixed / all / off |
| `approvals` | on | |
| `quietHours` | off | `{start: "22:00", end: "07:00"}` in the device's local time; **approvals are exempt** by default (`quietHours.exceptApprovals` on). A notification suppressed by quiet hours is dropped, not delayed (dropped ones still appear in the Activity feed when the app is opened). |
| `notActor` | on, **not editable** | the rule in §5.2; shown in the UI as a fixed line so people know why they do not hear about their own edits |
| `mutedArtifacts` | empty | `[{type, id, until}]` — "Mute this PR for a day" from the PR's app-bar menu; relay drops matches |

Settings UI: Settings → Notifications gets a "Push" section under the existing switch, one row per line above, read from the relay when opened, written on change (optimistic, with the existing snackbar on failure). Per-org: the section shows the org the account registered.

## 7. Uncertain payload shapes and the spikes that settle them

| spike | kind | what it does | needs |
|---|---|---|---|
| **s41** hook input values | read-only | **Done 2026-09-13.** `notificationType` has the four expected values; `mergeResult`, `buildStatus`, run/stage state and result values recorded in `research/spikes/results/README.md` | — |
| **w24** PR capture | scratch write | **Done 2026-09-13** (`w24_r2_capture.py`, modes `hooks` / `pr` / `shapes` / `delete`): 16 All-details subscriptions on `/capture/scratch-r2`, scratch PR 8348 (created, reviewer added, voted, pushed, commented with an `@<guid>` mention, retitled, abandoned), plus the w23 work item triggers. Every PR and work item shape in §1–§2 is verified from the key trees; the captures are wiped and the subscriptions deleted once the pipeline events are in. | — |
| **w25** pipeline capture | scratch write, **costs hosted minutes** | **Done 2026-09-13** (`w25_r2_pipeline_run.py`, `s43_wait_for_approval.py`): run 20260913.1 (build 20163) queued, Kelly approved Deploy from the Android emulator's Approvals tab, both stages succeeded (about 4 minutes of hosted time). Captured: `run-state-changed` ×2, `stage-state-changed` ×6, `approval-pending`, `approval-completed`, `build.complete` v2. The `scratch-r2` subscriptions were deleted and the captures wiped afterwards. | — |
| **s42** `workitem.commented` v1.0 body | part of w24 | **Done:** the v1.0 body carries `resource.commentVersionRef.commentId`, so the `?comment=` anchor is real and no newer resourceVersion is needed. | — |

None of these change relay or app code; they feed §2 and §8 and are the first phase of the build plan.

## 8. Decisions (Kelly, 2026-09-13)

| # | question | decision |
|---|---|---|
| D1 | Beta event set | **All five families**: work items, pull requests, PR comments, builds, approvals. One rule engine, the whole §2 acceptance table from the first release. |
| D2 | Work item `updated` default | **Assignment, state change and mention only.** Other field edits are silent unless the user turns on `workItems.anyChangeOnMine`. |
| D3 | Builds default | **Failures plus "fixed"** (a success right after a failure on the same definition and branch). Plain successes opt-in (`builds: all`). |
| D4 | PR comment audience | **Author, participants of the thread, reviewers who have voted, and mentioned users.** Per-user narrowing to "mentions only" or "my threads only". |
| D5 | Preferences | **On the relay per `(org, userId)`** through `GET/PUT /v1/prefs`; **quiet hours in the beta**, evaluated on the relay from the device's tz offset, approvals exempt by default. |
| D6 | Approvals on iOS | **Standard interruption level.** No time-sensitive entitlement in the beta. |
| D7 | Lock screen | **Android channel private**: the public version is the fallback line, the enriched body shows after unlock. iOS follows the system "Show Previews" setting (no per-notification control). |
| D8 | Spikes | **w24 and w25 both approved** (w25 spends about three hosted-agent minutes on the puremedia org; Kelly grants or rejects the Deploy approval from the phone). |
| D9 | Group reviewers and approvers | **Skipped in the beta and disclosed** to puremedia and on the prefs screen. Group expansion arrives with the service principal (s40). |
| D10 | `git.pullrequest.merged`, `approval-completed` | **Both in the beta** (dispatcher's call on the recommendation): merge failures to the author; completed approvals replace the pending notification. `stage-state-changed` and `run-state-changed` stay out. |

## 8a. R2.1 and R2.2 notes (2026-09-13, from the dispatcher's review)

- **PR status changes have no actor.** The `git.pullrequest.updated` body carries `closedDate` but no `closedBy`, so the relay cannot tell whether the author completed or abandoned their own PR. The author is notified either way (as the web's own e-mail does); a `pr_state`-based guess was rejected as unreliable. Accepted for the beta.
- **A vote's actor** is the reviewer whose `vote` differs from `pr_state`; when two votes moved in one delivery the author still hears, with no actor and no vote label.
- **PR validation builds do not yet notify the PR author:** `build.complete.triggerInfo["pr.number"]` is unverified (the scratch repo has no build policy), so `RoutingView` does not read it. Revisit when a customer pipeline with PR validation is in scope.
- **`run_state` is filled only by `run-state-changed`,** so an approval on a run queued before the relay started has no requester on record and every approver is asked. Acceptable.
- **`edited`** is computed from the changed fields minus a housekeeping set (comment noise plus `System.Reason`, board-column fields and the StateChange/Activated/Resolved/Closed dates), so a state change never also reads as an edit.
- Deep link for `approval-completed` is the project-scoped run route (`/projects/{p}/pipelines/runs/{runId}`), matching `Routes.pipelineRun`.
- The one relay-side text column is `projects.project_name`; a schema test pins every other routing table to id-only columns.
- **R2.3 choices (2026-09-13):** `UserPrefs.allows` takes verb, reason and detail (`votes: rejectionsAndWaitsOnly` needs the vote label) and quiet hours take the verb, so `quietHours.exceptApprovals: false` can silence approvals; `myThreadsOnly` keeps thread participants and mentions only, not the PR author; `mergeFailed`/`prCompleted`/`prAbandoned` fall under `pullRequests.completedAbandoned` and `prPublished` under `reviewRequested`; the build fallback body is "Build failed" (one pointer serves many recipients, so it cannot say "requested by you"); `POST /v1/test-push` sends the data-only Android shape, so the R1 app shows nothing for it until R2.4 posts the notification itself; `Verb` lives in `lib/src/verb.dart` above both `gateway/` and `routing/`, and `routing/` imports `gateway/`, never the reverse.
- Known test flake, untouched: `capture_test.dart` "caps the directory at maxFilesPerName" fails about one run in five under a full-suite load (timestamped filenames collide); it is the spike-3 recorder, not relay storage.

## 8b. Status (2026-09-13 evening)

R2.1–R2.6 and R2.8 are built, committed and, for the relay, deployed (see NEXT-STEPS item 19 for the commits). Live acceptance on the Android emulator against the scratch project: a deliberately failed build, an approval-pending push whose tap landed on the Approvals card and was granted there, and the "fixed" build afterwards — all delivered by FCM as data-only messages and enriched on the phone by the Kotlin path with the user's own token. Two facts learned on the way that changed this document: work item hooks must be at resourceVersion 5.1-preview.3 (§1.1) and the comment-shaped `workitem.updated` is the comment event (§2.1). **R2.7 (iOS Notification Service Extension) was built on the Mac on 2026-09-13** (`ios/BoardhopNotificationService/`, app group `group.com.kammcs.boardhop` + the `com.microsoft.adalcache` keychain group, MSAL silent token, the same six fetch paths and body formats as Kotlin, 42 XCTest cases, codesigned device build with the appex embedded) and **accepted on Kelly's iPhone on 2026-09-14**: `buildFailed` (run 20260914.2) and `approvalPending` (run 20260914.3) were both enriched by the extension with a silently acquired MSAL token in about a second, the approval tap landed on the Approvals card, the approval was granted there and the following `build.complete` pushed as `buildFixed` and was enriched the same way (breadcrumb: received → token acquired silently → enriched, all inside one second). The extension's own `NSLog` is invisible on this phone (the syslog relay stalls), so it keeps a breadcrumb file in the app group (`Library/Caches/push-extension.log`, metadata only) that `devicectl device copy from --domain-type appGroupDataContainer` pulls; NEXT-STEPS item 19 has the command. Two facts from the build: Apple's MSAL keeps its configuration in memory, so the vendored plugin mirrors it into the app group on request (`MsalAuthSharedDefaultsSuite`), and the APNs fallback lines live in `aps.alert`, not in data keys as on FCM, so `PointerData` takes them from the notification content. See NEXT-STEPS item 19.

## 9. Build plan (R2, dispatcher and Opus subagents)

Phases, each one subagent brief, each reviewed and committed by the dispatcher after `dart analyze`/`dart test` (relay) and `flutter analyze`/`flutter test` (app), with the emulator and the live relay as the acceptance rig:

- **R2.0 spikes** (s41, w24, w25 as approved) and the payload notes in `research/spikes/results/README.md`; the relay's test fixtures are built from **synthetic** payloads shaped like the captures (never the captures themselves, which hold client data even from the scratch project's identities).
- **R2.1 relay: ingest.** `POST /hooks/{org}` with basic auth per org, subscription registry (config file for the beta), dedup table, fast-200 with in-process queue, redacting logger, routing log. Tests: replay synthetic payloads, assert nothing from the body reaches disk or logs.
- **R2.2 relay: rules.** The audience engine as pure functions over a `RoutingView` (the ~15 fields the rules read), one file per family, the state tables in §5.1, mention extraction, noise filter, priority merge. Property tests for "actor never notified", "one per person", "no content in the pointer".
- **R2.3 relay: pointer v2 and prefs.** New pointer fields with caps and closed lists, APNs `mutable-content`/`thread-id`, FCM data-only HIGH, `GET/PUT /v1/prefs`, quiet hours, mutes, fan-out caps. `dart test` covers the payload size and the closed lists.
- **R2.4 app: pointer v2, prefs UI, feed insert.** `PushPointer` fields, verb → words, Settings → Notifications push section, pushed pointer inserted into the Activity feed, `notActor` line.
- **R2.5 app: routes and anchors.** `?comment=`, `?tab=`/`?thread=`, `?tab=approvals&approval=` with the page changes in §4.2 and widget tests for each anchor.
- **R2.6 Android enrichment.** `BoardhopMessagingService.onMessageReceived` → a small Kotlin client (MSAL Android silent token from the shared cache, three GETs) → `NotificationCompat` with public version, group, tag; fallback path; 8 s cap. Verified on the emulator against the live relay with w24/w25 events.
- **R2.7 iOS enrichment (Mac session).** `BoardhopNotificationService` NSE target: app group + `com.microsoft.adalcache` keychain group, MSAL silent token, the same three GETs in Swift, `mutable-content`, fallback. Verified on the iPhone.
- **R2.8 hooks provisioning for the beta.** `w22` generalized into the relay's own `tool/hooks.dart` that creates the thirteen subscriptions per project against `/hooks/{org}` with a per-org secret, used by hand for the scratch project and by the extension hub later.

Acceptance for the beta: from the scratch project, each row in §2 produces exactly the notification in the table on the Android emulator and on Kelly's iPhone, tapping lands on the anchor, and the routing log shows no body field.
