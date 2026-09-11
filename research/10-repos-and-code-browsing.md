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

## 7. Decisions for Kelly

1. **Home tab content**: the overview described in §3, or something lighter (just pinned repos and links)?
2. **"Short description"**: language line only, or read the README's first paragraph as the description (one extra cached call per repo)?
3. **Pull requests placement**: keep the org-level inbox on the project list app bar and make the repo page's link open it filtered by repo, or give Repos its own PR list per repo (the same widget either way).
4. **Favorites**: write the Azure DevOps favorite (syncs with the web star, per account) rather than a local-only pin. Recommended.
5. **Disabled / maintenance repos**: show with a badge at the bottom, or hide.
6. Anything from the GitHub app you want that is not here: file editing on mobile (Azure DevOps pushes API makes it possible; risky), releases/tags page (tags only, no releases concept), blame (no API).
