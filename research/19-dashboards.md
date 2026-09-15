# 19. Dashboards: the Dashboards view under the Home tab

Planned with Kelly on 2026-09-15 after four research passes: the Dashboard REST API and widget
settings shapes (spikes s57–s59, read-only), the data behind each widget (s60–s61, read-only), a
survey of Jira, monday, ClickUp, Asana, Trello, Linear, GitHub, Notion, Smartsheet, Power BI,
Grafana, Datadog and New Relic on phones, and an inventory of the app's reusable pieces. This is
the first of the two Home hubs from NEXT-STEPS 24 (Summary | Dashboards | Wiki); the pill ships with
two segments and Wiki slots in later. Decisions here; state in NEXT-STEPS item 26.

## 1. What the service does (verified 2026-09-15)

- **API is preview-only.** `api-version=7.1` is refused on every Dashboard resource
  (`VssInvalidPreviewVersionException`). Dashboards are `7.1-preview.3` (`{count, value}`), the
  widgets sub-resource `7.1-preview.2`, widget types `7.1-preview.1`. The first Boardhop API that
  cannot be pinned to a released version.
- **Routes.** `{project}/_apis/dashboard/dashboards` lists every team's dashboards (`groupId` =
  team, `dashboardScope` `project_Team` | `project`), **without widgets**. GET by id
  `{project}/{team}/_apis/dashboard/dashboards/{id}` returns `widgets[]` with `settings` (a JSON
  string, or null) inline; without the team segment it is 404. `7.1-preview.2` on the list still
  returns the old `DashboardGroup` with `teamDashboardPermission`, the only place the caller's
  rights are stated (read-only clients need nothing: all Project Valid Users can view).
- **Resources.** Dashboard: `id, name, description, dashboardScope, groupId, ownerId, position,
  refreshInterval (minutes, 0 = off), eTag (absent until edited), modifiedDate (moves on read),
  widgets[]`. Widget: `id, name, position{row, column} (1-based, 10 columns), size{rowSpan,
  columnSpan}, settings, settingsVersion, contributionId, typeId, configurationContributionId,
  isEnabled, lightboxOptions`. No evaluated data anywhere: every widget fetches its own.
- **Catalog.** `{project}/_apis/dashboard/widgettypes?$scope=project_Team` = 35 types (3 at
  `collection_User`), each with `name, description, catalogIconUrl, allowedSizes, analyticsServiceRequired,
  isVisibleFromCatalog`; `defaultSettings` null for every built-in. One cached call per org gives
  the name and icon of any contributionId the app does not know.
- **Defaults.** Every team gets one dashboard, "Overview", at creation; the current web creates it
  empty. All four puremedia projects have exactly one dashboard; three are empty (the scratch
  project's included), one client Overview holds 10 widgets: 2 Chart for Work Items, Query Tile,
  Burndown, Burnup, Velocity, Sprint Burndown (Legacy), Assigned to Me, Team Members, Work Links.
- **Settings shapes seen live** (GUIDs redacted): Query Tile `{queryId, queryName, lastArtifactName,
  defaultBackgroundColor, colorRules[]}`; Burndown/Burnup `{teams[{projectId, teamId}],
  workItemTypeFilter{identifier: BacklogCategory|WorkItemType, settings}, fieldFilters[{fieldName,
  queryOperation, queryValue}], aggregation{identifier: 0 count|1 sum, settings: field},
  timePeriodConfiguration{startDate, samplingConfiguration{identifier 0 date|1 iteration,
  settings{endDate, sampleInterval, lastDayOfWeek}}}, burndownTrendlineEnabled,
  totalScopeTrendlineEnabled, completedWorkEnabled, stackByWorkItemTypeEnabled,
  showResolvedItemsAsCompletedEnabled, includeBugsForRequirementCategory}`; Sprint Burndown adds
  `team{projectId, teamId}, iterationId, iterationPath, timePeriodConfiguration{startDate, endDate},
  isLegacy, isCustomized, showNonWorkingDays`; **Chart for Work Items is `{chartId}` only** and the
  chart definition has no public route (nine candidates 404, no Chart resource area); Velocity,
  Assigned to Me, Team Members, Work Links store `null`. Markdown's settings string is the markdown
  itself. Shapes never seen live (CFD, Cycle/Lead Time, Query Results, Build History, Code Tile,
  configured Velocity, Markdown's repo-file variant) come from the archived CloneAzdoDashboard
  models and are pinned by w36 (§5).
- **Data behind the widgets** (all verified; REST costs in TSTU, Analytics carries no rate header):
  - Query Tile / Results: `queries/{id}?$expand=wiql` (0.006) for `queryType`, `columns`;
    `wiql/{id}` (416 ids: 0.034, 0.26 s); `HEAD wiql/{id}` answers `X-Total-Count` without ids
    (0.065); `workitemsbatch` 200 ids × 9 fields 0.097. `WorkItemRepository.refreshQuery` already
    does the last two. **No chart API exists for a saved query.**
  - Burndown/Burnup: the `WorkItemSnapshot` `$apply` the sprint burndown runs, with the filter
    swapped from `IterationSK eq` to `Teams/any(t:t/TeamSK eq …) and {types} and DateValue ge/le`;
    30 days ≈ 1.1 s. `Processes?$filter=TeamSK eq … and BacklogType eq 'RequirementBacklog'`
    lists the level's types (`BacklogType` values are `RequirementBacklog|PortfolioBacklog|TaskBacklog`).
  - Velocity: `Iterations` (last N started), `WorkItems` grouped by `IterationSK` for completed /
    completed late (`CompletedDate le|gt Iteration/EndDate`, property compares work) / in progress
    (0.4 s each), and **one `WorkItemSnapshot` per iteration** for Planned (`IterationSK eq … and
    DateSK eq …`, 1.1 s each, run in parallel): an or-chain of six pairs took 55 s and `DateSK in`
    is 400.
  - CFD: `BoardLocations` (team's boards, then ordered columns, `IsCurrent eq true`) and
    `WorkItemBoardSnapshot` grouped by `(DateValue, ColumnName)` over the range (30 days 1.0–1.4 s;
    group by name only, `ColumnOrder` splits renamed columns).
  - Cycle/Lead Time: `WorkItems` completed in the range with `CycleTimeDays, LeadTimeDays,
    CompletedDate` (74 rows 0.35 s) plus an `aggregate(… with average)`.
  - Work by state/type: `WorkItems` groupby `(WorkItemType, State, StateCategory)`, 0.3 s.
  - Build History: `build/builds?definitions=&$top=20&queryOrder=finishTimeDescending` (0.027);
    pass rate from Analytics `PipelineRuns` aggregate (0.17 s, `RunOutcome` `Succeed|Failed|Canceled`).
  - Sprint Overview / Sprint Burndown: every call already in `SprintRepository` and
    `AnalyticsRepository`. Sprint Capacity: capacity is unused in every puremedia sprint.
  - Out of reach: Release Pipeline Overview and Deployment status (classic releases on vsrm, none
    active here), Test Results Trend and the test-plan widgets, Embedded Webpage (an iframe),
    Marketplace widgets.
- **Server-rendered PNGs exist** (`work/iterations/{id}/chartimages/Burndown`,
  `work/boards/{board}/chartimages/CumulativeFlow`, white background) and are not used (D14).
- **Favorites:** `artifactType=Microsoft.TeamFoundation.Dashboards.Dashboard`,
  `artifactScopeType=Project`. Web deep link `{org}/{project}/_dashboards/dashboard/{id}` (unverified).
- **Unverified:** the app's Entra token against `vso.dashboards` and against the Analytics entity
  sets beyond `WorkItemSnapshot` (D12 gates on the diagnostics check); `project`-scoped dashboards
  (none exist here); the deep-link form.

## 2. Best practice (survey)

Every native app that has dashboards is view-only and stacks widgets in one full-width column on
phones (Jira: a three-column web dashboard becomes one column, unsupported gadgets omitted with a
feedback link; monday: "widgets in full screen, scroll"; Power BI portrait: uniform tiles stacked,
landscape: the web canvas with pinch and pan, tap a tile for focus mode where drill-down lives;
Grafana: single column below the md breakpoint, Grafana 12's auto grid is the only vendor mechanism
yielding two columns at tablet width). Asana, Trello, GitHub Mobile and Linear ship no dashboards on
phones; Azure DevOps' own web on a phone is the desktop canvas. Smartsheet turns unrenderable embed
widgets into a tap-to-open link tile. Charts are native everywhere (legend tap to isolate a series,
long-press tooltips), and reviews punish apps whose charts cannot be enlarged. Refresh is
pull-to-refresh with a last-refreshed line; pickers are a list with favorite stars.

## 3. Decisions (Kelly, 2026-09-15)

| # | Decision |
|---|---|
| D1 | **Scope:** render the team's real Azure DevOps dashboards, plus a Boardhop-built **Team overview** offered when a dashboard is empty and listed in the picker as its own entry. |
| D2 | **Chart for Work Items** (unreadable `chartId`): show the query's count and a small breakdown by State (by type when every item shares a state) computed from the query's own results, with a note that the web's chart settings are not readable and an Open on web action. Flat queries only; tree queries show the count and list. |
| D3 | **Widgets in v1, all three tiers:** Query Tile, Query Results, Assigned to Me, Pull Requests, Team Members, Markdown, the link widgets (Work Links, Other Links, Welcome, VS Shortcuts, New Work Item), Build History; Burndown, Burnup, Sprint Overview, Sprint Burndown (Analytics and Legacy, both drawn from Analytics); Cycle Time, Lead Time, Cumulative Flow, Velocity. |
| D4 | **Layout:** phones stack widgets full width in reading order (row, then column). Tablets pack the web's spans into as many 168 dp columns as fit the content width (`min(webColumns, floor(width / 168))`, first-fit in reading order, `columnSpan` clamped), keeping the web's relative shape. Never a horizontal scroll. |
| D5 | **App bar:** the dashboard picker is the title (sprint pattern); the pill Summary \| Dashboards is the rightmost item; **Search stays on Summary only** (Wiki gets its own tree search later). |
| D6 | **Picker:** one project-wide list grouped by team, favorites first (read through the Favorites API, star shown read-only), then the Team overview entry; the last-opened dashboard is remembered per project; the default is the default team's Overview. |
| D7 | **Tap:** Query Tile, Query Results and Chart for Work Items open the query in the Work items page; Build History opens the pipeline; a PR row opens the PR; Assigned to Me rows open the item; links open their target (in-app route when one exists, otherwise the browser); charts open a **full-screen focus view** with the larger chart, legend and the data as a list, laid out for whichever orientation the phone is in. |
| D8 | **Pill:** two segments now (Summary \| Dashboards); the enum, routes and switch are shaped for Wiki as the third. |
| D9 | **Team overview (built-in), six cards:** sprint burndown (current sprint), work by state, cumulative flow (30 days), cycle and lead time (60 days), velocity (last 6 sprints), pipeline pass rate (90 days). Each loads and degrades on its own. |
| D10 | **Unsupported widgets are hidden** (Release, Test, Embedded Webpage, Marketplace, and any widget whose settings fail to parse), with a footer line "N widgets not shown in Boardhop" that opens the dashboard on the web. |
| D11 | **Scratch test data:** a write spike (w36) adds one widget of every unseen kind to the scratch project's empty Overview dashboard and reads the settings back; they stay as acceptance data. |
| D12 | **Refresh:** cache-first open with "Updated N min ago" under the title, pull-to-refresh refetches the dashboard and every widget. `refreshInterval` is ignored (no timers). |
| D13 | **Icons:** Summary `Icons.summarize_outlined`, Dashboards `Icons.dashboard_outlined` (Wiki later `Icons.menu_book_outlined`). |
| D14 | **Analytics refusal:** each Analytics card shows "Analytics unavailable" with the reason while REST-backed cards render; the Diagnostics page gains a dashboards token check (Dashboard API and the extra OData entity sets) that the build runs on the simulator before the chart phase. **No server-rendered PNGs**: the CFD is native `fl_chart`; Sprint Burndown (Legacy) draws the Analytics burndown its settings' iteration id points at. |
| D15 | **Focus view** follows the device orientation: legend below the chart in portrait, beside it in landscape; no forced rotation. |

## 4. Design

### 4.1 Data: `lib/data/models/dashboard.dart`, `lib/data/repositories/dashboard_repository.dart`

- Models: `Dashboard {id, name, description, scope, teamId (groupId), position, refreshInterval,
  widgets}`, `DashboardWidget {id, name, contributionId, row, column, rowSpan, columnSpan,
  settings (raw string), settingsJson (lazy, null when not JSON), settingsVersion, isEnabled}`,
  `DashboardSummary` for the list, `WidgetKind` (an enum derived from the contributionId suffix,
  `unknown` otherwise), typed settings parsers per kind (`QueryTileSettings`, `BurndownSettings`,
  `SprintBurndownSettings`, `VelocitySettings`, `CfdSettings`, `CycleTimeSettings`,
  `QueryResultsSettings`, `BuildHistorySettings`, `CodeTileSettings`, `MarkdownSettings`), each
  tolerant of missing keys and returning null on a shape it does not understand (→ hidden, D10).
- `DashboardRepository` in `AccountDeps`: `list(org, project)` (project route, all teams, cached
  `dashboard:list:{org}:{project}`, 24 h), `get(org, project, teamId, id)` (cache-first
  `dashboard:{org}:{project}:{id}`), `favorites(org, project)` (Favorites API, cached), `catalog(org,
  project)` (widget types, cached 7 days, used only for names of unknown kinds in the footer line),
  `cachedDashboard`. Reads only; there is no dashboard write in the app.
- Widget data goes through the owning repository's cache where one exists (`query:{id}` via
  `WorkItemRepository.refreshQuery`, runs via `PipelineRepository.runs(definitionId, queryOrder)`,
  `SprintRepository`, `AnalyticsRepository`); `AnalyticsRepository` gains public typed queries
  (`teamBurndown`, `velocity`, `cumulativeFlow`, `cycleAndLeadTime`, `workByState`, `pipelineOutcomes`)
  with cache keys `analytics:{kind}:{org}:{project}:{team}:{args}:{day}` and the 1 h TTL, each
  refusing through `AnalyticsUnavailable`.
- `DashboardPrefs` (copy of `SprintPrefs`): last dashboard id per project.

### 4.2 Widgets: `lib/features/dashboards/`

- `home_view_switch.dart` in `lib/features/projects/widgets/`: `enum HomeView {summary, dashboards}`
  and `HomeViewSwitch` cloned from `WorkViewSwitch` (icon-only on phones, D13).
- `dashboard_page.dart`: app bar per D5 (title = picker, `if (!compact)` a picker icon,
  `HomeViewSwitch`), body `SafeArea(top:false, bottom:false)` → `RefreshIndicator` → `ContentColumn`
  → one `CustomScrollView`; cached copy first with the "Updated N min ago" line; empty dashboard →
  the Team overview offer (D1); footer line for hidden widgets (D10).
- `dashboard_layout.dart`: the pure grid mapper (D4), unit-tested at 390, 700 and 1120 dp and xxxL.
  Tablet card height `rowSpan × 160 × boardTextScale.clamp(1, 1.6)`; phone cards intrinsic with a
  per-kind cap (charts 220, lists N rows then See all).
- `widgets/registry.dart`: `WidgetKind → DashboardCardBuilder`; every card is a `StatefulWidget`
  that loads its own data (cache first), handles `AdoAuthException` → `AuthInteractionRequired`, other
  `AdoException` and `AnalyticsUnavailable` inline (D14), and exposes `onTap` per D7.
- Cards: `query_tile_card`, `query_results_card` (a lifted work item row), `assigned_to_me_card`,
  `pull_requests_card` (`PullRequestTile`), `team_members_card` (`IdentityAvatar`), `markdown_card`
  (`MentionMarkdown`, clamped with More), `links_card`, `build_history_card` (`fl_chart` bars,
  `BoardhopColors.run*`), `burndown_card` (existing `SprintBurndownChart` fed by `teamBurndown`),
  `sprint_overview_card`, `velocity_card` (grouped bars), `cfd_card` (cumulative lines with
  `belowBarData`), `cycle_time_card` (scatter + rolling average), `work_item_chart_card` (D2).
- `team_overview.dart`: the six D9 cards as a synthetic `Dashboard`.
- `chart_focus_page.dart`: the full-screen focus route (D7/D15), pushed over the shell, receiving the
  card's data.
- `picker_sheet.dart`: `showDashboardPicker` (75 % sheet, grouped by team, favorites first, Team
  overview last).
- Diagnostics: `/diagnostics/dashboard` with canned widgets (no client data) and the token check
  rows (D14).

### 4.3 Router

`Routes.home`, `Routes.dashboards(account, org, project, {dashboard})` (id omitted = last opened
or the default team's Overview), `Routes.chartFocus`; `GoRoute ':project/dashboards'` in the Home
branch beside `home` and `search`; the focus page outside the shell like `workItemStandalone`.
`_bleedsUnderRail` unchanged; `ProjectShell._destinations` unchanged.

## 5. Acceptance

1. w36 has added the unseen widget kinds to the scratch Overview; every one parses, and the three
   settings kinds seen on the client dashboard parse from the redacted spike output in tests.
2. iPhone 17 and iPad Pro 13" simulators, debug builds, both themes, xxxL: the scratch Overview
   renders every card; the client Overview renders its 10 widgets minus none (all 10 are D3 kinds)
   with the Chart for Work Items cards per D2; the empty dashboards offer the Team overview and it
   draws all six cards on the client project.
3. Picker: grouped by team, favorites first, Team overview entry, last-opened remembered, `?dashboard=`
   deep link.
4. Taps per D7, including the focus view in portrait and landscape.
5. Offline (widget tests): cached dashboard and cards draw, pull-to-refresh reports the failure.
6. Diagnostics token check passes for the Dashboard API and every OData entity set used; if any
   refuses, the affected cards show the D14 notice.
7. `flutter analyze` clean, suite green; walkthrough under `research/walkthroughs/`.

## 6. Out of v1

Wiki (the third segment), dashboard writes (create, favorite, reorder), `refreshInterval` timers,
Release and Test widgets, Embedded Webpage, Marketplace widgets, Sprint Capacity (no capacity data
anywhere), Chart for Work Items trend types, the Query Results widget's column choice on phones,
a Boardhop-authored phone layout per dashboard, PNG charts.
