# 15. Search across Azure DevOps content

**Status:** planned with Kelly 2026-09-14 (interview below), spike s44 done, **built and accepted the same day** (S1–S3, see NEXT-STEPS item 20 and `research/walkthroughs/2026-09-14-search.md`). Decisions S2/S3 made where this document was silent are in their sections of the walkthrough: the route lives in the shell's Home branch; the scope switch is page state, not a navigation; facets are remembered from the last unfiltered answer; paging is infinite scroll; a title match is bolded in the title itself and the extra line is kept for description/history matches.

## 1. What exists

- Code search, project-scoped, through the Code Search extension (`RepoRepository.searchCode`, `CodeSearchPage`, opened from Repos and from a repository). Results carry no snippets; a hit opens the file at the hit's branch and the viewer finds the first line with the term.
- Type-to-filter on the repository list and the branch picker.
- Nothing for work items or pull requests, and no single place to search from.

## 2. What the service offers (spike s44, read-only, 2026-09-14)

| kind | call | facts |
|---|---|---|
| work items | `POST almsearch.dev.azure.com/{org}[/{project}]/_apis/search/workitemsearchresults?api-version=7.1`, body `{searchText, $skip, $top, filters, $orderBy, includeFacets}` | Built in on Services (the puremedia PAT reaches it). Project scope by path **or** by `filters.System.TeamProject`; other filter keys `System.WorkItemType`, `System.State`, `System.AssignedTo`. `includeFacets: true` returns `facets` for those four keys as `[{name, resultCount}]` (org-wide "test": 7,687 hits, 4 projects, 10 types, 17 states). `$orderBy: [{field: "system.changeddate", sortOrder: "DESC"}]` works; default is relevance. `$top` 201 was honoured (no cap hit; the app pages by 50). A 2-character term and a nonsense term both answer `count: 0` with `infoCode: 0`, so "type 3 characters" is a client rule, not a service one. Each result: `fields` with **lower-case** reference names (`system.id`, `system.title`, `system.workitemtype`, `system.state`, `system.assignedto` as `Name <email>`, `system.tags`, `system.changeddate`, `system.createddate`, `system.description`, `system.history`, `system.rev`), `hits: [{fieldReferenceName, highlights: [String]}]` (the highlighted fragment with `<highlighthit>` markup; title, description, history and tags all appear), `project: {id, name}`, `url`. |
| code | `codesearchresults`, same host | Works org-wide without a project in the path (568 hits for "TODO" across 2 projects, `facets.Project`); today the app only calls it per project. |
| wiki | `wikisearchresults` | Answers; out of v1 (no wiki reader in the app). |
| pull requests | none | Titles, branches and authors matched **client-side** over the org-level active PR list the app already fetches (spike S4). |
| pipelines, repos | `build/definitions?name=*text*`; none | Out of v1 (interview). |

## 3. Decisions (Kelly, 2026-09-14)

| # | question | decision |
|---|---|---|
| D1 | Scope | **Current project by default, with an "All projects" switch** (org-wide through the Search API's project facet; PRs are org-wide already). |
| D2 | Kinds in v1 | **Work items, code, pull requests.** Pipelines and repos out; wiki out until there is a wiki reader. |
| D3 | Entry point | **Search icon on the project Home app bar**, opening a full-screen search view. The dock keeps four tabs. |
| D4 | Work item filters | **Type and State chips from the facets** under the field (no assignee chips in v1). |
| D5 | Recents | **Last 10 queries per account, on the device**, under the empty field; tap re-runs, swipe removes, cleared on sign-out. Nothing leaves the phone. |
| D6 | Snippets | **Title plus one highlighted line** from the hit's highlight (fetched with the user's own token like every read). |
| D7 | PR scope | **Active PRs across the org** we already list, matched locally; no completed PRs in v1. |
| D8 | Trigger | **As you type, debounced**: from 3 characters, 400 ms after the last keystroke; PR matches are instant from local data, API kinds follow. |
| D9 | Layout | **Grouped sections with See all**: Work items, Code, Pull requests, up to 5 hits each with the total; See all opens that kind's full list with chips and paging. |
| D10 | Work tab | **An inline filter field** above the assigned-to-me list, local only. |

Constants: minimum 3 characters, debounce 400 ms, 5 per section in the grouped view, 50 per page in See all, 10 recents.

## 4. Design

- **Route:** `…/projects/{project}/search?q=&scope=project|org&kind=` (account-scoped like everything else). `kind` set = the See-all view of one kind; unset = grouped.
- **Screen:** the app bar holds the text field (autofocus, clear button) and the scope switch (segmented pill Project | All, the rightmost app-bar item per DESIGN.md). Below: recents when the field is empty; grouped sections while a query is live; each section header has the kind, the total and See all. Work item rows: `#id · type` tile (AdoTiles), title, one highlighted line, state and assignee; code rows as `CodeSearchPage` draws them; PR rows as the PR list draws them. Chips (type, state) only in the work item See-all view. Every state (loading per section, empty, error inline, offline with the cached copy) is drawn; pull-to-refresh re-runs the query.
- **Data:** `SearchRepository` over the bound `AdoClient` with `searchWorkItems(org, {project?, text, types, states, skip, orderBy})`, `searchCode(org, {project?, text, repository?, skip})` (moves the existing call, org-wide allowed), `searchPullRequests(org, {project?, text})` (local over `PullRequestRepository.list(filter: all, status: active)`). Every API read caches JSON per `(account, org, project?, kind, text, filters, page)` so a re-opened search shows the cached copy first, and the cached copy is what an offline phone gets. `SearchRecents` in shared preferences per account. `AdoAuthException` raises `AuthInteractionRequired`; other `AdoException`s show inline per section.
- **Highlights:** `<highlighthit>…</highlighthit>` becomes bold text; everything else is plain text (HTML in the description highlight is stripped the way `EnrichmentFormat.plainText` does).
- **Taps:** work item → `Routes.workItem` (project from the hit, so All-projects hits open in their own project); code → the file at the hit's branch as today; PR → `Routes.pullRequest`.
- **Work tab:** a field above the list filters the loaded items by id, title, type, state and assignee; no API call.

## 5. Build plan (dispatcher + one Opus subagent per phase, reviewed and committed by the dispatcher)

- **S1 data.** Models (`WorkItemSearchHit`, `SearchFacets`, `SearchResults<T>`), `SearchRepository`, `SearchRecents`, cache keys, highlight parsing, unit tests with canned JSON in the s44 shape (synthetic values, never the captures).
- **S2 UI.** `SearchPage` (grouped and See all), chips, recents, scope switch, debounce, routes, the Home app-bar icon, the Work tab filter field; widget tests; compact and expanded; light and dark.
- **S3 acceptance.** Simulator walkthrough (iPhone 17, iPad Pro 13", both themes, dynamic type xxxL) with screenshots sent to Kelly; findings fixed; NEXT-STEPS and this document updated.

Acceptance: from the scratch project, "boardhop" finds the spike work items with a highlighted line, All projects widens to the org with the project on each row, a PR title fragment finds PR 8348, code hits open the file, chips narrow the work item list, recents persist across a restart, and the Work tab field narrows the assigned-to-me list.
