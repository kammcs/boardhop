# 10. Repos and code browsing: research and plan

**Date:** 2026-09-11
**Ask (Kelly):** beyond pull requests, let people browse code, branches and history the way the GitHub app does; reorganize the bottom menu (Home / Work / Repos / Pipelines, with Work holding both the work item list and the board behind a top selector); a Repos tab with a repository picker and a repo page showing a pull-requests link, the current branch with a way to change it, links to code and commit history, and the README rendered underneath.
**Method:** spike s17 against CloudCover 2.0 (read-only; results in `research/spikes/results/README.md`), Microsoft Learn docs research, and a survey of GitHub Mobile, GitLab/Bitbucket clients and the existing Az DevOps app.

## 1. What Azure DevOps gives us (verified)

| Need | Endpoint (all `dev.azure.com/{org}/{project}/_apis/git/repositories/{id}` unless noted) | Verified on puremedia |
|---|---|---|
| Repository list | `GET …/_apis/git/repositories` 7.1 | 26 repos; fields: `name, defaultBranch, size, isDisabled, isInMaintenance, project, remoteUrl, sshUrl, webUrl` (+`isFork`, `parentRepository` on forks). **No description, no language.** |
| Primary language | `GET {project}/_apis/projectanalysis/languagemetrics` 7.1-preview.1 (undocumented on Learn, typed in the extension SDK) | One entry per repo with `languageBreakdown[] {name, files, filesPercentage, bytes}`; MonitorIT = TypeScript 73% / Java 19%. Some repos come back empty. |
| Favorite / pin | `GET/POST/DELETE {org}/_apis/Favorite/Favorites` 7.1-preview.1, `artifactType=Microsoft.TeamFoundation.Git.Repository`, `artifactScopeType=Project` | Read works (Kelly has none). The write half is the same object the web "star" uses; needs the w11 spike on the scratch repo. Favorites are per user per org, so they sync with the web. |
| Branches | `refs?filter=heads/&includeStatuses=true&latestStatusesOnly=true` and `stats/branches` (ahead/behind vs default, tip commit author, date, message) | Both one call each. Tags via `refs?filter=tags/&peelTags=true`. |
| Commits | `commits?searchCriteria.itemVersion.version={branch}&$top&$skip` (+`itemPath` for file/folder history, `author`, `fromDate`) ; `commits/{id}?changeCount=` ; `commits/{id}/changes` | Lists carry `changeCounts`; detail carries `parents`, `push`, `changes[] {item.path, changeType}`. |
| Branch compare | `diffs/commits?baseVersion=&targetVersion=&$top&$skip` | `aheadCount, behindCount, commonCommit, changeCounts, changes[]`. |
| Folder listing | `items?scopePath=/x&recursionLevel=OneLevel&versionDescriptor.version=` | Children carry `path, gitObjectType, objectId, commitId` only; **no per-child content metadata and no paging**. Always one level; drill down. |
| File content | `items?path=&includeContent=true&$format=json` (plain string `content`) or `Accept: text/plain`; `items?path=&includeContentMetadata=true` for `isBinary, isImage, encoding, contentType`; `blobs/{sha}` bare = `{size}` | README (14 kB) both ways; a PNG reports `isBinary: true, isImage: true`. Gate downloads on `blobs/{sha}.size` before fetching. |
| README | No API; `items?path=/README.md` at the default branch (probe `README.md`, `readme.md`, `README` in that order, the web does a case-insensitive root lookup) | Found on MonitorIT. |
| Code search | `POST almsearch.dev.azure.com/{org}[/{project}]/_apis/search/codesearchresults` 7.1, body `{searchText, $top, $skip, filters:{Project[], Repository[], Path[], Branch[]}}` | 568 org-wide / 408 project hits for "TODO"; a `Repository` filter without `Project` is a 400. Results give `path, fileName, repository, project, versions[], matches{content, fileName}`; **no snippets** (open the file and jump to the first match). Needs the Code Search extension; `infoCode` flags "indexing" / "not enabled". |
| Recently viewed | Not exposed (internal MRU) | Keep our own recents locally, as the web's cannot be read. |
| Blame / annotate | Not in the REST API | Out of scope. |

Scopes: everything is `vso.code` except favorites (`vso.profile`) and language metrics (`vso.analytics`, worked with the current token).

## 2. What the GitHub app and peers do

- **GitHub Mobile repo screen:** owner/name, description, Star / Watch / Fork row, then Code (README rendered first, then the tree with a branch picker), Issues, Pull Requests, Actions, Projects. Directory "History" opens the commits for that path. The file viewer has no syntax highlighting (a long-standing user complaint), code search covers the default branch only. Navigation was recently *reduced* to Home + Inbox as the backbone; Home mixes a feed with pinned and recent repos.
- **GitLab (GitAlchemy) and Bitbucket clients:** project rows with a language color dot, starred/pinned first, CI status on the repo page, syntax-highlighted file views, side-by-side diffs.
- **Az DevOps (PurpleSoft):** repos, commits with file diffs, PRs; a flat list, no README, no branch picker worth copying.
- **Repo list rows everywhere:** avatar or letter tile, name, one descriptive line, language dot, private badge, "updated 3d ago", a star that pins. Star (pin) is kept visually separate from Watch (notifications).

**Takeaways for Boardhop:** ship syntax highlighting in the file viewer on day one (we already have the highlighter from the PR diff work), render README first, keep a branch picker with the default marked and ahead/behind visible, show commits with avatars and relative time, keep four tabs.

## 3. Proposed information architecture

Bottom navigation inside a project (Kelly's mockup):

| Tab | Content |
|---|---|
| **Home** | Project overview: pinned repos, my open PRs and PRs to review in this project, work items assigned to me (top 5), latest pipeline runs, project description. Replaces nothing that exists; it is the landing page after picking a project. |
| **Work** | Top segmented control **Items · Board** over today's Work items page and Boards page (state preserved per segment). The saved-query chips stay inside Items. |
| **Repos** | Repository list → repository page → code, commits, branches, PRs, search. |
| **Pipelines** | Unchanged. |

The org-level bell (activity) and the org-level PR inbox stay in the app bar of the project list; project-level PRs move under Repos and Home.

### 3.1 Repository list (Repos tab root)

Row: letter tile in the web's project-tile style (`AdoTiles`) since Azure DevOps has no repo image · **name** · secondary line built from what exists: primary language (from language metrics) with a color dot, default branch name, size ("TypeScript · main · 25 MB"); a **star** toggle at the trailing edge that writes the Azure DevOps favorite. Sections: *Favorites* first, then *Recent* (local, last five opened), then *All* alphabetically; disabled and in-maintenance repos at the bottom with a badge. Search field filters by name. Forks show "forked from X".

The mockup's "Short description" cannot come from the service; the language line is the honest substitute. If Kelly wants a real description we could read the first paragraph of the README (one extra call per repo, cached), which is what GitHub effectively shows.

### 3.2 Repository page

Header: tile, name, star, "Open in browser" (webUrl). Then, as in the mockup, a list of navigation rows:

1. **Pull requests** (count of active PRs targeting this repo; opens today's PR list filtered by repo).
2. **Branch row**: current branch (default on first open) with ahead/behind against the default branch and the tip commit's author and age; tapping opens the branch picker (search, default marked, tags section, last activity per branch).
3. **Code** (opens the folder browser at the chosen branch).
4. **Commits** (history of the chosen branch).
5. **Search in this repo** (code search, when the extension is enabled).
6. **README** rendered below with `flutter_markdown_plus`; relative images resolved through the Items API with the bearer token, relative links opened in the code browser, HTML blocks ignored. Falls back to "No README" and the language breakdown bar.

### 3.3 Code browser and file viewer

- Folder view: breadcrumb, folders first, then files, one level per request (the API has no paging). Long-press or a row menu: History (path history), Copy path, Open in browser.
- File view: syntax highlighting through the existing `CodeHighlighter` (extension map already covers the CloudCover stacks), line numbers, wrap toggle, monospace scale, "History", "Copy link", "Open in browser". Images render inline (`isImage`), other binaries show size and type with a download-in-browser link. Files over 1 MB open with a warning and a "Load anyway"; the size comes from the bare blob call before the content request.
- Highlighting runs off the UI thread via the same isolate path the diff view uses (a listed later item in NEXT-STEPS; do it here).

### 3.4 Commits

- List for the current branch: avatar (identity avatars already cached), first line of the message, author, relative time, change counts. Infinite scroll with `$skip`. A path filter when opened from History.
- Commit page: full message, author/committer, parents, linked work items (`includeWorkItems`), changed files with change types; tapping a file shows the diff using the existing diff engine, feeding it the file at the parent commit and at the commit (Items API by `commitId`), the same way the PR diff page does.
- Branch compare: from the branch picker, "Compare with default" shows `diffs/commits` counts and changed files.

### 3.5 Search

Project-level code search page (from the Repos root and the repo page with the repository pre-filtered): results grouped by repository with path and match counts; tapping opens the file at the result's branch and scrolls to the first match. Handle `infoCode` for "not enabled" and "indexing" with plain messages.

## 4. Data layer

- `lib/data/models/git_repository.dart` (`GitRepository`, `GitRef`, `BranchStats`, `GitCommit`, `GitItem`, `RepoLanguage`, `Favorite`, `CodeSearchResult`).
- `lib/data/repositories/repo_repository.dart` over the bound `AdoClient`: `list(org, project)` cached in a new drift table `repositories` (shared across accounts like projects), `languages(org, project)` cached as JSON per project (24 h), `favorites(org)` in the account namespace, `setFavorite`, `branches`, `branchStats`, `tags`, `commits`, `commit`, `changes`, `items`, `content`, `metadata`, `blobSize`, `diff`, `readme`, `search`. File contents in a small in-memory LRU plus the existing `CacheEntries` for the last 20 files so a file reopens offline.
- Recents: `repo:recent:{org}` list in the account namespace.
- Routes (account-scoped like everything else): `…/projects/{project}/repos`, `…/repos/{repo}`, `…/repos/{repo}/code?ref=&path=`, `…/repos/{repo}/file?ref=&path=`, `…/repos/{repo}/commits?ref=&path=`, `…/repos/{repo}/commits/{id}`, `…/repos/{repo}/branches`, `…/projects/{project}/search`. The activity feed gains commit routes later.

## 5. Phases and effort

| Phase | Scope | Estimate |
|---|---|---|
| 0 | Navigation reorganization: four tabs (Home placeholder with the project description and quick links, Work with the Items/Board segmented control, Repos, Pipelines); routes and tests updated. | 0.5 day |
| 1 | Repository list with language, favorites (after spike w11), recents, search-as-you-type; repository page with the mockup's rows and the README. | 1.5 days |
| 2 | Code browser and file viewer (highlighting off the UI thread, images, binary and size gates, history and link actions), offline reopen of recent files. | 1.5 days |
| 3 | Branch picker with stats and tags, commits list, commit page with per-file diffs, branch compare. | 1.5 days |
| 4 | Code search page, Home tab content (pinned repos, my PRs, my items, latest runs), tablet two-pane for browser + file, polish. | 1 day |

Each phase ends with emulator screenshots and a push; phases 1 to 3 are the ones to review visually.

## 6. Spikes before phase 1 (scratch project only)

- **w11**: favorite the scratch repository through the API (`POST Favorites` with `artifactType=Microsoft.TeamFoundation.Git.Repository`, `artifactScopeType=Project`, `artifactScopeId={projectId}`, `artifactId={repoId}`), read it back, delete it. Confirms the write shape and that the web shows the star.
- Language metrics on the scratch project (tiny repo) to see the "empty result" case the docs warn about.
- Code search `infoCode` values: the puremedia org has the extension; note the response shape and test the disabled case only if another org is available.
- A large-file probe (`items` on a 5 MB blob) for timing.

## 7. Decisions (interview with Kelly, 2026-09-11)

1. **Home tab** = project overview: pinned repos, my PRs and PRs to review in this project, work items assigned to me, latest pipeline runs, project description.
2. **Repo row second line** = language · default branch · size. No README scraping.
3. **Pull requests**: the repo page opens the existing PR list filtered by repository; the org-level inbox stays on the project list app bar; the project-level PR tab goes away (its route stays for deep links).
4. **Favorites** are written to Azure DevOps (sync with the web star, per signed-in account). Spike w11 first.
5. **Disabled / in-maintenance repos** are shown at the bottom with a badge.
6. **Branch row** starts on the default branch and then remembers the last pick per repository on the device.
7. **Extras in scope**: a tags page (tags with their commit; no releases concept in Azure DevOps), share / copy link for files, folders and commits (web URL through the share sheet), and **editing a file from the phone**: a highlighted editor (`re_editor`, same author and grammars as the `re_highlight` package the diff view uses; verify in a spike, fall back to a monospace field), text files under 200 KB only, the commit lands on a new branch named from the user's alias and the file, and a sheet then offers to open a PR against the branch that was being viewed. That works with branch policies and never pushes to a protected branch directly.
8. **Order**: shell first (phase 0), then repositories.

Phase 5 (added): tags page, share links, file editing with `re_editor` and the pushes API already used for suggestion apply — about 1.5 days.

## 8. Phase 2 notes (2026-09-11)

- Routes: `…/repos/{repo}/code?ref=&path=` (folder) and `…/repos/{repo}/file?ref=&path=[&line=]` (file). Both resolve the repository object through `_RepoRoute` in `lib/router.dart` (cached list first, then the network), so deep links work cold.
- The Items API marks SVG as text (`isImage` false), so `.svg` files show as XML source; PNG/JPG come back with `isImage: true` and load through `$format=octetStream`, which honours the bearer token where `Image.network` cannot.
- File flow on open: cached copy (if any) → `items?includeContentMetadata=true` → `blobs/{sha}` size → skip the download when the cached object id matches → content. Text above 1 MB waits for "Load anyway"; above 20 MB it is refused; highlighting is skipped above 300 KB.
- Highlighting runs in `Isolate.run` (`CodeHighlighter.highlightLinesAsync`); `re_highlight` registers grammars lazily so a fresh isolate is cheap, and `TextStyle` runs cross the isolate boundary as plain objects. Plain rows are shown while the grammar pass runs.
- Markdown links inside repository files resolve against the file folder (`RepoPaths.resolve`): a target with an extension opens the file viewer, one without opens the folder.
- Deferred to later phases: jump-to-line from search (the `line` query is already honoured), History (phase 3 commits route with `path`), share sheet (phase 5).

## 9. Phase 3 notes (2026-09-11)

- Routes: `…/repos/{repo}/commits?ref=&path=`, `…/commits/{id}`, `…/diff?path=&old=&new=&change=&original=`, `…/compare?base=&ref=`. Tags live in the branch picker as a second segment (no separate page needed; a tag row opens its commit, the code icon browses files at the tag).
- `GitVersion.query(ref)` turns any ref string into a `versionDescriptor` (40-hex → commit, `refs/tags/x` → tag, else branch), so `code`, `file`, `commits` and `diff` all accept a branch name, a tag ref or a commit id.
- `POST commitsbatch` with `includeWorkItems` is the only read that returns linked work items for a known commit, but it omits `parents`; `GET commits/{id}` has the parents. The commit page needs both and merges them.
- Merge commits from squash-merged PRs have one parent and per-file counts; true merge commits list no changes of their own.
- Compare uses `diffs/commits` with the common ancestor as the old side of each file diff and the target commit as the new side; `allChangesIncluded=false` is shown as "(first N)".
- Not built: commit list filters (author, date), blame (no REST API), share sheet (phase 5).

## 10. Phase 4 notes (2026-09-11)

- Code search request: `POST almsearch.dev.azure.com/{org}/{project}/_apis/search/codesearchresults?api-version=7.1` with `{searchText, $skip, $top, filters: {Project: [project], Repository?: [name]}, includeFacets: false}`. `matches.content` may be a list of offsets or a count; both are read as a count. No snippets and no line numbers, so the viewer locates the first line containing the term client-side.
- Routes: `…/projects/{project}/code-search?q=` (project) and `…/repos/{repo}/search?q=` (repository). `code-search` sits beside `repos` rather than under it because `repos/search` would collide with a repository named "search".
- Home tab reads the five latest runs with `cache: false` so the Pipelines tab keeps its 50-run cached list; PR lists reuse the project-scoped cache keys the PR page uses.
- Two-pane: `CodeBrowserPage` at medium/expanded width keeps the folder list at 38% of the width (300–420 px) and shows `FilePage(embedded: true)` on the right; folders still push a new browser page so the back gesture keeps working.

## 11. Phase 5 notes (2026-09-11)

- `re_editor` 0.10.0 (MIT, same author and grammars as `re_highlight`) works on Flutter 3.47: `CodeEditor(controller: CodeLineEditingController.fromText(text), style: CodeEditorStyle(codeTheme: CodeHighlightTheme(languages: {lang: CodeHighlightThemeMode(mode: builtinLanguages[lang])}, theme: …)), indicatorBuilder: … DefaultCodeLineNumber(...))`. `controller.text` reads the edit back; the controller normalizes to `
`, so the page restores `
` when the original used it. Mobile selection toolbar is the default one; no custom `toolbarController` yet.
- Commit flow: `POST refs` `[{name: refs/heads/x, oldObjectId: 0…0, newObjectId: tip}]` then `POST pushes` with `refUpdates[].oldObjectId = tip` and one `edit` change with `rawtext` content; then `POST pullrequests` `{sourceRefName, targetRefName, title, description}` → `pullRequestId`. The tip is the `commitId` from the file's `items?includeContentMetadata=true` read, so a concurrent push to the same branch would fail rather than be overwritten.
- Branch name: `alias/stem-MMdd-HHmm`, alias = sign-in name before `@`, sanitized for Git (`RepoRepository.sanitizeBranchName`). The person can change both the message and the branch in the sheet.
- `share_plus` resolved to 12.0.2 (13.x needs a newer `web` constraint than the other packages allow); API `SharePlus.instance.share(ShareParams(uri:, title:))`.
- Verified on the scratch repo: README.md edit → a8c9baa on `kkamm/readme-0911-1024` → PR 8336 opened in the app.

