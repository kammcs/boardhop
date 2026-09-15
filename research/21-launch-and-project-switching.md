# 21 — Launch experience and project switching

**Status:** planned with Kelly 2026-09-15 (interview below); built the same day in dispatcher mode
(two Opus phases in parallel, LA state/routing and LB picker/bell), accepted on the Android
emulators (§6). Not yet on iOS.

**Kelly's ask (verbatim intent):** "On root level project pages, we will remove the back arrow to
project nav and replace it with a project picker that shows the logged in users with a log out
option, the ability to log in as another user, the activity screen nav link, the settings nav
link. This menu sits under the logo of the currently active project. Whatever project you had open
the last time you had the app open will be where you start, on the home tab. After logging in the
first time, you land on the first project in that user's list, with the ability to tap the project
logo to open the picker. This request comes from users who feel it takes too many taps to get into
the project to start with 95% of the time."

## 1. Today

Splash → `/orgs` (the Organizations page: every signed-in account with avatar, name, sign-out,
its organizations; app bar with Add account, Diagnostics in debug, Settings) → an org's project
list (app bar with Activity bell and "PRs to review") → the project shell, four tabs (Home, Work,
Repos, Pipelines), each root page with its own `AppBar` whose leading is a back arrow to the project
list. Three taps to reach Home every cold start. `OrgRepository.lastOpened/markOpened` already
remembers the last org per account (drift `organizations.lastOpenedAt`); nothing remembers the
project.

## 2. Decisions (Kelly, 2026-09-15)

| # | Decision | Choice |
|---|---|---|
| L1 | Picker scope | **Everything in one sheet:** each signed-in account as a section (avatar, name, email, Sign out), its organizations as subheads, every project as a row, the current project ticked. Bottom rows: Add account, Manage accounts, Activity, Settings (Diagnostics in debug builds). One tap reaches any project. |
| L2 | Presentation | **Modal bottom sheet on compact widths** (draggable, opens at ~60 %, drags to full), **an anchored panel under the logo at medium and expanded widths** (360 dp wide, at most 70 % of the height). |
| L3 | Old pages | **Keep both routes, out of the main flow.** `/orgs` becomes "Manage accounts" reachable from the picker; the project list stays for deep links and the org row. Only the launch redirect changes. |
| L4 | Logo affordance | **Project tile plus a small ▾ chevron** in the leading slot of all four root tabs (Home, Work, Repos, Pipelines), replacing the back arrow. Titles stay as they are. |
| L5 | Activity | **Bell in the root app bars plus the picker row.** A bell with an unread dot beside the magnifier on Home and in the other root tabs' action rows, opening the current org's Activity. |
| L6 | Account changes | **Add account → that account's first project. Sign out of the active account → the remaining account's remembered (or first) project; no accounts left → sign-in.** |
| L7 | Ordering and fallback | **Alphabetical org, alphabetical project** (as the lists today). A remembered project that no longer exists or is no longer accessible falls back to the first available and says so in a snackbar. |
| L8 | Cold start | **Straight to the shell from stored ids, cached-first.** The remembered account/org/project builds the route with no network call; Home paints from its cache. Only the first sign-in fetches the org and project lists on the splash. |

Decided without asking (dispatcher): the picker gets a filter field once it lists more than eight
projects; the picker's Activity row and bell show the same unread dot; the remembered project is
one per device (not per account) since "whatever you had open last" is device state; the tab is
always Home on launch (Kelly's words), tabs inside a session are unchanged.

## 3. Shape

```
cold start, signed in
  splash ──► LaunchResolver.resolve(accounts)
              │ remembered (account still signed in)  ──► /a/{acc}/orgs/{org}/projects/{proj}/home
              │ else first account → orgs by name → projects by name (cache, then network)
              │ nothing at all ──► /orgs
              ▼
        project shell: root tabs carry [tile ▾] ── tap ──► ProjectPicker
                                                             accounts ▸ orgs ▸ projects (✓ current)
                                                             Add account · Manage accounts · Activity · Settings
```

Entering any project route writes `LastProject(accountId, org, project)`; the resolver reads it.

## 4. Contract between the two build phases

**Phase LA — state and routing** (`lib/data/last_project.dart`, `lib/features/launch/`,
`lib/router.dart`, `lib/app.dart`):

- `class LastProject { accountId, org, project }` and `class LastProjectStore` over
  `shared_preferences` (`launch.last.account|org|project`): `read()`, `write()`, `clear()`.
- `class LaunchResolver` with `Future<LaunchTarget> resolve(List<Account> accounts, {String? preferAccountId})`:
  - `preferAccountId` set (a just-added account): that account's first org/project (L6), ignoring the store;
  - otherwise the stored project if its account is still in `accounts` (no verification, L8);
  - otherwise the first account in `accounts`, orgs by name, projects by name, from the caches
    first (`OrgRepository.watch().first`, `ProjectRepository.watch(org).first`) and the network
    (`refresh`) only when a cache is empty;
  - nothing → `Routes.orgs`.
  - Returns `LaunchTarget(route, fallback: LaunchFallback?)`; `fallback` names why the stored
    project was not used (`accountGone`, `none`) so the shell can say so.
- Exposed as `RepositoryProvider<LaunchResolver>` at the app root: `context.read<LaunchResolver>()`.
- Router: `redirect` for `AuthSignedIn` at `/` or `/sign-in` returns the resolved route
  (go_router accepts a `FutureOr<String?>` redirect). Everything else unchanged; `/orgs` stays.
- The project `ShellRoute` builder (or `ProjectShell`) writes the store on entry, debounced to one
  write per route change. A `LaunchNotice` (`ValueNotifier<LaunchFallback?>`) is set by the
  resolver and consumed once by `ProjectShell`, which shows the L7 snackbar ("Your last project
  isn't available any more; opened {project}") on the shell's `ScaffoldMessenger`.
- Project-not-found at runtime (L7, the remembered project was deleted): the Home page already
  shows its error inline; the resolver does not pre-verify (L8). If the project stream reports the
  project missing after the first refresh, `ProjectShell` offers "Choose another project" which
  opens the picker (LB's `showProjectPicker`, reached through a callback so LA has no UI dependency
  on LB during the build).

**Phase LB — picker and app bars** (`lib/features/projects/widgets/project_picker_*.dart`,
the four root pages, `lib/features/activity/`, `lib/data/repositories/activity_repository.dart`):

- `ProjectPickerButton(org, project)` for the `leading` slot: the project's tile
  (`Project.tileSource` avatar when there is one, otherwise `AdoTile` colour and initials, 28 dp)
  plus a chevron, tooltip "Switch project"; replaces the back arrow on Home, Work, Repos, Pipelines.
- `showProjectPicker(context, {org, project})`: bottom sheet at `Breakpoint.compact`
  (`DraggableScrollableSheet`, initial 0.6), an anchored panel otherwise (L2). Content per L1,
  built from `AuthSignedIn.accounts` (their `OrgRepository.watch()` and `ProjectRepository.watch(org)`
  per account through `AppDependencies.forAccount`), sorted by name, current project ticked, a filter
  field when more than eight projects. Rows `context.go` to `Routes.home(...)`. Sign out and Add
  account go through `AuthBloc` and then `context.read<LaunchResolver>().resolve(...)` → `context.go`
  (L6). Manage accounts → `/orgs`; Activity → `Routes.activity(account, org)`; Settings → `/settings`;
  Diagnostics → `/diagnostics` when `AppConfig.diagnosticsEnabled`.
- Activity bell: `ActivityRepository.unread(org)` (`Stream<int>`: cached items newer than the seen
  timestamp) feeding an `ActivityBell` with a dot; on Home beside the magnifier (left of the pill),
  in the other three root tabs' action rows left of their existing actions.
- The Organizations page's role text: its app bar title becomes "Accounts"; nothing else changes.

## 5. Acceptance (Android emulators, both widths, both themes)

1. Cold start signed in with a remembered project lands on its Home with no intermediate page;
   kill and relaunch after opening a different project lands there.
2. First sign-in on a fresh install lands on the first alphabetical project of the first account.
3. The tile ▾ opens the picker on all four tabs; every project row switches; current is ticked;
   the sheet drags to full height; the tablet panel anchors under the logo.
4. Sign out of the active account with a second account present lands on that account's project;
   with none, on sign-in. Add account lands on the new account's first project.
5. Activity bell dot appears with unread items and clears after opening Activity.
6. `/orgs` and the project list still open from the picker and from a deep link.
7. Remembered project removed from the store by hand (or an account signed out) → fallback with the snackbar.

## 6. Acceptance on Android (2026-09-15, Pixel 10 Pro and Pixel Tablet emulators, debug build)

Passed: (1) cold start with an empty memory landed on CloudCover 2.0, the first alphabetical
project, with no intermediate page; after switching to the scratch project, kill and relaunch landed
there. (3) the tile ▾ opens the picker from all four tabs; rows switch and the current row is ticked;
the sheet drags to full height; the tablet panel anchors under the tile. (5) the bell dot showed with
5 unread and cleared after opening Activity. (7) a remembered project that does not exist (the
preference edited by hand to "Gone Project"): the shell opened it (L8, no pre-check), the Home
sections showed the service's TF200016 lines, and the snackbar "\"Gone Project\" is not available
any more · Choose another project" appeared with the first frame; the action opens the picker. Both
themes on the phone.

Two defects found and fixed on the way: switching projects reused the root pages' state, so Home
kept the previous project's body under the new header — the four root routes now key their page by
org and project (`router.dart`); and the sheet drew two drag handles (the theme's and the content's
own) — `showDragHandle: false`.

Not exercised: (4) sign out with a second account and Add account (one account on the emulator; the
code path waits for the bloc's next state and is unit-tested); (2) a fresh install's first sign-in
(needs Kelly's credentials); (6) deep links into `/orgs` (the picker's Manage accounts row opens it).

Observation for Kelly: with the tile, Search, the bell and the three-segment Home pill, the Home
title truncates to "DevO…" at phone width, and the Work tab's two-line title likewise. The header
below already names the project, so dropping the app-bar title text on Home at compact width is the
obvious fix; decision left to Kelly.
