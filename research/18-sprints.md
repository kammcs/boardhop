# 18. Sprints: the Sprint view under the Work tab

Planned with Kelly on 2026-09-15 after three research passes (Azure DevOps facts with spikes
s54/s55 and w33–w35; a survey of the web Sprints hub, Jira, Trello, Asana, ClickUp, Linear,
GitHub Projects and Planner on mobile plus the chart libraries; a map of the app's board, iteration
and picker code). Decisions here; state in NEXT-STEPS item 25. Layout goal: NEXT-STEPS 24 (the
Work pill becomes Items | Board | Sprint).

## 1. What the service does (verified)

- **Iterations:** `GET {project}/{team}/_apis/work/teamsettings/iterations?api-version=7.1` → the
  whole list (cap 100, `$top` ignored), `attributes.timeFrame` past|current|future computed even
  when dates are null; **`$timeframe` accepts only `current`** (anything else is 400). `teamsettings`
  gives `defaultIteration`, `backlogIteration`, `workingDays`, `bugsBehavior`. The iteration GUID
  equals the classification node's `identifier`. A first read of a 100-iteration team took 19 s once;
  cache a day and warm it off the critical path. Every puremedia project has exactly one team.
- **The sprint's items, one call:** `GET …/teamsettings/iterations/{id}/workitems` →
  `workItemRelations`: `source: null` rows are roots (requirements, or unparented tasks), rows with
  `source` are children under their parent, roots already in ascending `StackRank`. It pulls in
  parents from other iterations whose child is in this sprint and drops hidden types. Prefer it to
  WIQL. Then `workitemsbatch` for the fields.
- **Taskboard columns:** `GET …/work/taskboardcolumns?api-version=7.1-preview.1` answers
  `{columns: [], isCustomized: false}` on **three of four projects**, and `taskboardworkitems` then
  answers 400 `TaskboardColumnNotCustomizedException`. The app must derive columns from the state
  category first: `backlogconfiguration.workItemTypeMappedStates` + `wit/workitemtypes/{type}/states`
  → Proposed = To Do, InProgress (+Resolved) = In Progress, Completed = Done. When customized,
  `taskboardworkitems/{iterationId}` gives each task's explicit column (needed only where one state
  maps to several columns; the placement is sticky).
- **Moving a task:** a plain `System.State` patch (with `test /rev`) moves the taskboard column;
  `PATCH …/taskboardworkitems/{iter}/{id}` `{"newColumn": name}` (204) only sets the column among
  those mapped to the item's *current* state and never writes the state. Reorder within a cell:
  `PATCH {team}/_apis/work/workitemsorder` `{ids, previousId, nextId, parentId}` (writes StackRank).
- **Types:** `backlogconfiguration` `taskBacklog.workItemTypes` vs `requirementBacklog`;
  `bugsBehavior` decides whether Bug is a row or a card (CloudCover: rows). The Order field is
  `Microsoft.VSTS.Common.StackRank` in all four projects.
- **Capacity / days off / Remaining Work are unused everywhere** (0 members with capacity in any
  sprint, Remaining Work on 0 of 149 items). Capacity read: `…/iterations/{id}/capacities`
  (collection is `teamMembers`). Remaining Work patch refuses `null`; send 0 to clear; no rollup.
- **Burndown:** Analytics OData `https://analytics.dev.azure.com/{org}/{project}/_odata/v4.0-preview/
  WorkItemSnapshot` with `$apply=filter(IterationSK eq {guid} and DateValue …)/groupby((DateValue,
  StateCategory), aggregate($count as Count, StoryPoints with sum as SP))` → one row per day and
  category in ~1.3 s, no rate cost; `IterationSK` equalled the iteration GUID here (keep the
  `Iterations` lookup as fallback). Hours are not available in practice. **The app's Entra token
  against the Analytics host is unverified** (only the PAT was tried); `vso.analytics` is registered.
- **Only CloudCover 2.0 runs dated sprints**; its current sprint had ended with no next one and the
  service still calls it current. Its taskboard would hold 5 task-type items against 143 rows.
- No sprint-goal API exists. Costs: a cold taskboard load ≈ 0.77 TSTU / 1.1 s; every write < 0.1.

## 2. Best practice (survey)

No mainstream mobile app renders a two-dimensional board on a phone: Jira tested the grid and
rejected it; Jira, Trello, Asana and Planner keep the state axis and page columns at ~80–90 % width;
Linear and GitHub Projects drop the board for a grouped list. Drag is offered but never load-bearing:
every product keeps a menu path (WCAG 2.2 2.5.7 requires a single-pointer alternative, and idb cannot
long-press-drag on the simulator). The parent is a badge or a header, not a lane. Sprint selection is
a picker in the chrome defaulting to current. Charts are a summary, not the page. Tablets get the
grid back with full-width collapsible row headers and a supporting pane. Chart library: `fl_chart`
1.2.0 is MIT, adds no new transitive packages, is theme-agnostic and has `dashArray` and step lines;
Syncfusion is rejected on licence. Accessibility of any chart is our own work (a `Semantics` label
over an `ExcludeSemantics` chart plus the day-by-day numbers as a list).

## 3. Decisions (Kelly, 2026-09-15)

| # | Decision |
|---|---|
| S1 | **Where:** the third segment of the Work pill, Items \| Board \| Sprint; route `…/projects/{project}/sprint?iteration=…&tab=…` (iteration omitted when current). The sprint page bleeds under the iOS rail like the board. |
| S2 | **Tabs inside the page: Backlog, Taskboard, Burndown** (a counted tab strip like the PR page). Backlog = the sprint's requirement rows ordered by rank with task counts and rollups; Taskboard = tasks in state columns; Burndown = the chart page. Opens on Taskboard when the sprint has task-type items, else Backlog; the last tab is remembered per project. |
| S3 | **Writes:** move a task between columns (drag and a tap-to-move sheet: a state patch, plus the column call when the state maps to several columns); set Remaining Work (stepper, 0 clears) and assign to me from the card sheet; add a task under a story (the New card row, parented, in the sprint); move an item into or out of the sprint from the Backlog tab (an iteration-path patch). |
| S4 | **Phone taskboard:** one `KanbanBoard` with tasks in state columns; a chip strip picks All \| Unparented (first, only when non-empty) \| one story; cards carry the parent id as the badge when unfiltered. The drag code is reused unchanged. |
| S5 | **Tablet taskboard:** a real rows × columns grid (`TaskboardGrid`): one vertical scroller, sticky column headers with count and remaining sum, full-width collapsible row headers (title, id, state, rollup, task count, +), cells as tall as the tallest, horizontal scroll only as overflow. ~~Burndown and capacity in a supporting pane at expanded width.~~ **Superseded by S13: no pane, the grid takes the viewport.** |
| S6 | **Burndown:** Analytics items-remaining by day with story points as a second series; a text verdict and a sparkline in the sprint header, the full chart (ideal line dashed, non-working days banded) on the Burndown tab; `fl_chart` pinned, behind one widget. The text summary ships regardless; the chart is built only after the on-device token check passes, and if the host refuses the app's token the tab says so. |
| S7 | **Capacity:** read-only, shown only when the team filled it for that sprint (a strip on the Backlog tab, the pane on tablets). Never edited. |
| S8 | **Team:** the project's default team; the sprint picker sheet names the team and offers a switch when the project has more than one. No app-bar control. |
| S9 | **Offline:** the sprint snapshot is cached (JsonCache + drift list) and drawn first; a move offline queues as a `System.State` patch (the column call is not queued); the Kanban board gets the same treatment now (it never read its cached cards back). |
| S10 | **People:** an app-bar person filter with Everyone, Me, and members with task counts. No group-by-people layout. |
| S11 | **Admin:** no sprint creation or date editing in v1. The picker lists current, future, past; undated sprints are shown greyed "Dates not set". |
| S12 | **An ended sprint** the service still calls current opens as current; the header says "Ended N days ago"; the burndown covers its dates. No day count when dates are missing. |
| S13 | **The Taskboard tab carries no header and no chart** (Kelly, after seeing it on real data: the tiles and sparkline made the board harder to see). The sprint header stays on Backlog and Burndown; on tablets the grid takes the full width and height, with no supporting pane beside it. The capacity strip stays on the Backlog tab and the full chart with its facts on the Burndown tab, so nothing is lost — it moves. |

## 4. Design

### 4.1 Data: `lib/data/repositories/sprint_repository.dart`
Registered in `AccountDeps` as `sprints`. Reads through `_cached` with `sprint:*` keys:
`iterations(org, project, team)` (reuse `WorkItemFormRepository.teamIterations`; split on timeFrame);
`columns(org, project, team)` → `List<TaskboardColumn>` from `taskboardcolumns` when customized else
derived from `backlogconfiguration.workItemTypeMappedStates` + type states (cached per type);
`load(org, project, team, iterationId)` → `SprintSnapshot{iteration, columns, rows:[SprintRow{parent?,
tasks}], unparented, byColumn, fetchedAt}` from `iterations/{id}/workitems` + `workitemsbatch`
(fields: Id, Title, WorkItemType, State, AssignedTo, Parent, IterationPath, AreaPath, RemainingWork,
StoryPoints, StackRank; RemainingWork/StoryPoints guarded by the process's field list) + the explicit
columns when customized; `capacities(...)` lazily; static pure helpers `distribute`, `moveOps`
(state for the target column's mapping of that type), `columnFor(item)`, `rollup(row)`. Writes:
`move`, `setColumn`, `reorder` (reuse `BoardRepository.reorderBlock` with `parentId`),
`setRemainingWork`, `setIteration`. Snapshot stored under drift list key `sprint:{iterationId}` and
`JsonCache` `sprint:snapshot:{org}:{project}:{team}:{iteration}`; the board gets the same
(`board:snapshot:…`) and its page renders the cached snapshot first.
`AnalyticsRepository.burndown(org, project, iterationId, start, end)` over the OData host with the
bearer token: `List<BurndownDay{date, remaining, done, points}>`, cached by (iteration, lastDay);
`AnalyticsUnavailable` typed exception on 401/403.

### 4.2 Widgets: `lib/features/sprints/`
`SprintPage` (app bar: two-line title project / sprint name + dates or "Ended N days ago"; actions:
person filter, sprint picker (sheet grouped Current / Future / Past, team name, team switch),
`WorkViewSwitch(sprint)`; `CountedTabBar` Backlog | Taskboard | Burndown), `SprintHeader` (stat tiles
remaining / done / scope, sparkline, verdict), `SprintBacklogTab` (rows: type tile, id, title, state,
rollup, task count, tap → work item; overflow: Move to another sprint; capacity strip when present),
`SprintTaskboardTab` (phone: chip strip + `KanbanBoard`; tablet: `TaskboardGrid` alone, S13),
`TaskboardGrid` (new, shares the drag session pieces with `KanbanBoard` via an extracted helper),
`TaskCardSheet` (Move to … per column, Remaining Work stepper, Assign to me, Open), `SprintBurndownChart`
(fl_chart behind one widget; `Semantics` label; sparkline and full modes), `SprintPickerSheet`.
Cards: `WorkItemCard` with `badge` = remaining work or parent id. Move choreography extracted from
`BoardsPage._move` into a shared helper both pages use. Column header height follows the text scaler.

### 4.3 Router
`Routes.sprint(account, org, project, {iteration, tab})`; `GoRoute ':project/sprint'` beside
`':project/boards'`; `ProjectShell._bleedsUnderRail` matches `/sprint`; `WorkView.sprint` with its own
icon; `Routes.workItems`/`board` helpers so the switch stops concatenating strings.

## 5. Acceptance
1. Scratch project: the Sprint view opens on Iteration 1 (current), Taskboard tab, derived columns To Do / In Progress / Verify / Done (the scratch board is customized) with the 11 tasks under their stories and the unparented row first; the picker lists Iteration 2 as future; switching keeps the tab.
2. Drag a task To Do → In Progress: state patch, column follows; the sheet does the same by tap; a column that shares a state (Verify) uses the column call; Remaining Work stepper writes and clears; assign to me; New task under a story lands in the sprint with the parent link; Move to another sprint from the Backlog tab.
3. CloudCover 2.0 (read-only): its current sprint has moved on since this was written — **133 requirement rows and 16 task-type items** — so it opens on the **Taskboard** (S2 firing on the data, not a defect); rows ordered by rank with rollups; person filter Me (0 for Kelly there); the ended sprint reads "Ended N days ago".
4. Burndown: the diagnostics probe confirms the Entra token against Analytics; the chart draws for CloudCover's sprint with the dashed ideal line; the scratch sprint (no history) shows the verdict only; the tab explains when Analytics refuses.
5. Offline: airplane on the simulator is not possible; widget tests cover the cached snapshot first and a queued move; the board opens from cache after the fix.
6. iPad: grid with sticky headers and collapsible rows taking the whole pane (S13 removed the supporting pane); dark; xxxL (cards wrap, chip strip id-only); phone landscape.

## 6. Out of v1
Group by people; capacity editing; sprint creation and dates; sprint goal (no API); reordering tasks
within a cell on the phone (sheet only); moving stories between sprints by drag; multi-team probes
(every project here has one team).

## 7. What landed (2026-09-15)

P-A: `lib/data/models/sprint.dart`, `SprintRepository` (derived columns, one-call rows, cached
snapshot, moves and reorders, Remaining Work, iteration moves, teams), `AnalyticsRepository`
(`AdoHost.analytics`, `AnalyticsUnavailable`), `BoardRepository`/`BoardsPage` cache-first (S9).
P-B: `DragSession` extracted from `KanbanBoard`, `TaskboardGrid`, `TaskCardSheet`,
`SprintBurndownChart` (fl_chart 1.2.0), `SprintHeader`, `SprintPickerSheet`, `PersonFilterMenu`,
`StoryChipStrip`, burndown colour tokens, a diagnostics probe. P-C: `Routes.sprint/workItems/board`,
the `':project/sprint'` route, `WorkView.sprint`, `SprintPage` with the three tabs, the shared
`runMoveChoreography`, the `WorkItemCard` xxxL fix. P-D: acceptance on the iPhone 17 and iPad Pro
13" simulators, the team switch finished (spike s56: every puremedia project has one team), the phone
title, the sparkline band, S13, and four device defects fixed (units in the header and column headers
after Remaining Work is cleared, a stale iteration in the route after a team switch). §5 items pass
except the device-impossible three (a real drag, airplane-mode offline, the Analytics-refused
sentence), which widget tests cover. Report: `research/walkthroughs/2026-09-15-sprints.md`.

