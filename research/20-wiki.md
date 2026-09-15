# 20. Wiki: the read-only Wiki view under the Home tab

Planned with Kelly on 2026-09-15 after four research passes: the Wiki REST API and the link forms
(spikes s62/s63 read-only, w37 scratch writes), a rendering assessment of the app's markdown stack
against the wiki's extensions, a survey of Confluence, Notion, GitHub, GitLab, Obsidian, Loop,
OneNote and others on phones, and an inventory of the app's reusable pieces. This is the third and
last Home hub from NEXT-STEPS 24 (Summary | Dashboards | Wiki). **Read-only**: editing is a later
phase by Kelly's decision. Decisions here; state in NEXT-STEPS item 27.

## 1. What the service does (verified 2026-09-15)

- **One API family** at `{org}/{project}/_apis/wiki/wikis/{wikiIdOrName}/…`, `api-version=7.1`
  (non-preview), scope `vso.wiki`, already on the registration and consented (research/09).
- **Wikis:** `GET wikis` → `{id, name, type projectWiki|codeWiki, projectId, repositoryId,
  mappedPath, versions[{version}], remoteUrl}`. A project has 0 or 1 project wiki and N code wikis
  (a repo folder published per branch, up to 10). The project wiki's `repositoryId == id`; its repo
  is hidden from `git/repositories` but every `git/repositories/{wikiRepoId}` route works. puremedia
  has one client project wiki (134 pages, depth 5, 168 attachments, 40 `.order` files, 0
  non-conformant pages) and, since w37, the scratch `DevOps-Mobile-App.wiki`.
- **Tree:** `pages?path=/&recursionLevel=full` returns the whole tree in one call (0.07 TSTU for
  134 pages) with `path` (title form, spaces kept), `gitItemPath` (file form: space→`-`,
  hyphen→`%2D`), `order`, `isParentPage`, `isNonConformant`, `subPages[]` **and no `id`**. Ids come
  from `POST pagesbatch` (`{top, continuationToken, pageViewsForDays}`, paged through the
  `x-ms-continuationtoken` header, 0.004 TSTU) or from a per-page GET. Never derive one path form
  from the other (research/01 §8); join batch rows to tree nodes on `path`.
- **Page:** `pages?path=…&includeContent=true` or `pages/{id}?includeContent=true` → `{id, path,
  gitItemPath, order, content, subPages, remoteUrl}`; `Accept: text/plain` returns the raw markdown.
  The `ETag` header is the page's git blob SHA (equals search's `contentId`); `If-None-Match` is
  ignored (always 200), so it is a client-side change key only. Missing path → 404
  `WikiPageNotFoundException`; a bad version → 500 `GitUnresolvableToCommitException`. A git-pushed
  file with a space in its name is `isNonConformant: true` and 404s by path and id (show greyed,
  not openable). `stats` and `pagesbatch` carry 30-day view counts.
- **Attachments:** `/.attachments/name.png` in the wiki repo. No wiki GET exists; bytes come from
  `git/repositories/{wikiRepoId}/items?path=/.attachments/…&versionDescriptor.version={branch}`
  with the bearer header (free of TSTU) — the app's `RepoRepository.fileBytes` unchanged. The
  attachment PUT (write, not used) wants a base64 body despite the docs.
- **Bulk:** the whole wiki as one zip (`items?scopePath=/&download=true&$format=zip`, 13.7 MB,
  1.3 s, no TSTU); page history through `commits?searchCriteria.itemPath=` (0.035 TSTU).
- **Search:** `POST almsearch…/{project}/_apis/search/wikisearchresults` → hits `{fileName, path
  (git file path), wiki{id, name, mappedPath, version}, project, contentId, hits[{fieldReferenceName
  fileNames|content, highlights[]}]}`, facets `Project`/`Wiki`; org-wide or project-scoped; the
  index lags new pages by minutes.
- **Linking from elsewhere:** a work item takes an `ArtifactLink` relation `url:
  vstfs:///Wiki/WikiPage/{projectId}%2F{wikiId}%2F{Page%2FPath}` with `attributes.name "Wiki Page"`
  (verified on #15545, rev 32). **Comments have no wiki mention syntax**: a page is referenced by
  its web URL; the web's Copy page URL gives the id form
  `…/{project}/_wiki/wikis/{wikiName}/{pageId}/{Title-With-Hyphens}` (9 in client pages), the REST
  `remoteUrl` the path form `…/_wiki/wikis/{wikiId}?pagePath=%2F…[&wikiVersion=GB…]`. Inside wiki
  pages `#123` and `!123` auto-link (194 uses on 38 client pages) and `@<guid>` mentions people (2
  uses); none writes a relation.
- **Markdown census (client wiki, counts only):** `[[_TOC_]]` 11 pages, `[[_TOSP_]]` 7, tables 911
  rows on 21 pages, task lists 68, code fences 40, attachments 152 refs, HTML `<div>/<font>/<span>/
  <center>/<br>` 44, 2 `query-table`; **zero** front matter, mermaid, math, video, footnotes,
  `<details>`, sized images, and zero relative wiki-path links (cross-page links are absolute web
  URLs). Anchor ids: lowercase, spaces to hyphens, punctuation dropped (the docs' own example).
- **Scratch test data (quotable):** wiki `2bd59283-17a5-4fd0-b964-cd9a4189f721` (branch
  `wikiMaster`), pages `/Boardhop` 236 (`[[_TOSP_]]`), `/Boardhop/Constructs` 238 (every construct),
  `/Boardhop/Links` 240 (relative links in every form), `/Boardhop/Links/Deep child` 242,
  `/Boardhop/Links/Re-Order` 244, `/Boardhop/Links/Deep child/Level 4` 246, `/Boardhop/Pushed page`
  248 (non-conformant), `/Boardhop/Pushed tidy` 249 (outside `.order`); attachment
  `/.attachments/boardhop-w37-b64.png`; #15545 carries the Wiki Page link to Constructs.
- **Unverified:** what the web itself writes for a Wiki Page link (no client item has one); code
  wikis end to end (none exist); the app's Entra token against `_apis/wiki` and wiki search
  (expected fine, `vso.wiki` is consented; the diagnostics check settles it).

## 2. Best practice (survey)

Confluence mobile is the model: an in-place expandable tree per space, recents and starred as the
entry points, space-scoped search, unsupported macros as tappable placeholders that open on the
web, images in an in-app viewer, dark mode from the system, a three-column iPad. Notion linearises
columns and keeps its floating TOC desktop-only; Obsidian is the best phone markdown reader (edge
swipe tree, outline pane); GitHub Mobile cannot read wikis and its universal links hijack wiki URLs
into an app that shows nothing (claim only URLs you can render); GitLab's web tree collapses at
phone widths. Everyone pushes a new page on an internal link, sends `#id` to the issue, and the
rest to the browser. Read-only apps show no edit control and an explicit "Open on web".

Rendering: stay on `flutter_markdown_plus` with custom syntaxes and builders (the pattern
`MentionMarkdown` already uses) so highlighting, authenticated images, the lightbox, mention
routing and link colour are shared with comments and READMEs; `flutter_widget_from_html_core` for
raw HTML blocks; no new packages. `markdown_widget` (16 months without a release, a second
highlighter) and a WebView of the wiki SPA (needs a browser session, unthemeable, offline-hostile)
were weighed and rejected.

## 3. Decisions (Kelly, 2026-09-15)

| # | Decision |
|---|---|
| K1 | **Landing:** the page tree, expanded along the last-read path, with up to five recent pages above it; the wiki's home page opens on the very first visit. |
| K2 | **Tree:** in-place expandable on phones (chevrons, ancestors visible, current page highlighted). |
| K3 | **Placeholders:** mermaid, KaTeX math, `::: video` and `::: query-table` render as labelled cards with Show source and Open on web; query tables also open the query in the Work items page. No new renderer packages in v1; a WebView mermaid focus page may follow. |
| K4 | **Search:** a fourth grouped section on the Search page (project and All scopes, title hits first) plus find-in-page in the reader with up/down. |
| K5 | **Links from elsewhere:** tapped wiki URLs in comments and HTML fields open the in-app reader (both web URL forms, name or guid segments); the Related tab shows Wiki Page artifact links and plain hyperlinks; the comment composers gain a wiki-page picker that inserts `[Page title](url)` at the caret. No relation writes. |
| K6 | **Tablet:** from the medium breakpoint the tree stays in a leading pane with the page beside it (work items list+detail pattern); phones push the page over the shell. |
| K7 | **Offline:** cache as you read (tree, pages, images on disk); whole-wiki download later. |
| K8 | **Code wikis:** listed in the picker, same reader, a branch switcher beside the title, every read passes the version; recorded as unverified until a code wiki exists. |
| K9 | **Page chrome:** title and parent path; a contents button opening a headings sheet when the page has two or more headings (in-place `[[_TOC_]]` renders too); overflow with Open on web, Copy link, Show source; a footer line "Last changed by A on date · Edit on the web" from one commits call. No edit affordance. |
| K10 | **Tables:** a custom table builder — columns capped at about 80 % of the viewport so cells wrap, wider tables pan sideways, header row shaded. |
| K11 | **Recents only** (five per wiki, on the device); no starring in v1. |
| K12 | **Composer picker trigger:** a book button beside attach opening a sheet with the tree and a search field; no typed trigger. |

## 4. Design

### 4.1 Data: `lib/data/models/wiki.dart`, `lib/core/text/wiki_link.dart`, `lib/data/repositories/wiki_repository.dart`

- `Wiki {id, name, type, projectId, repositoryId, mappedPath, versions, version (first), remoteUrl,
  isProjectWiki}`; `WikiPageNode {id?, path, title, gitItemPath, order, isParentPage,
  isNonConformant, subPages}` with `flatten()`, `find(path)`, `ancestorsOf(path)`;
  `WikiPage {id, path, gitItemPath, content, etag, subPages, remoteUrl}`; `WikiSearchHit`;
  `WikiPageChange {author, date, comment}`.
- `WikiLink` (pure Dart): parses the two web URL forms and the `vstfs:///Wiki/WikiPage/…` artifact
  URI into `{org, project, wikiIdOrName, pageId?, path?, version?, anchor?}`; resolves a wiki-relative
  href (`/A/B`, `./C`, `../D`, `#anchor`, `A/B#anchor`, `/.attachments/x`) against a page path;
  builds the id-form URL for the composer picker; anchor id from heading text (docs' example rule,
  hyphen-collapsed fallback on a miss).
- `WikiRepository` in `AccountDeps`: `wikis(org, project)` (cache `wiki:list:…`), `tree(org,
  project, wikiId, {version})` (`recursionLevel=full` then `pagesbatch` pages joined on `path` for
  ids; cache `wiki:tree:…`), `page(org, project, wikiId, {path | id, version})` (cache-first
  `wiki:page:…` keyed by path, ETag stored), `cachedPage`, `attachmentBytes` (delegates to
  `RepoRepository.fileBytes` with the wiki repo and version; disk cache through
  `CachedNetworkImageProvider(itemsUrl, headers)` for images), `lastChange(org, project, wiki,
  gitItemPath)` (commits, cached), and `SearchRepository.searchWiki(org, project?, text, {skip, top})`.
  Reads only.
- `WikiPrefs` (copy of `DashboardPrefs`): last wiki, last path, recents (five) per org/project/wiki.

### 4.2 Widgets: `lib/features/wiki/`

- `HomeView.wiki` in `HomeViewSwitch` (`Icons.menu_book_outlined`, D13).
- `wiki_tree_page.dart` (Home branch): app bar title = wiki name with the type line, an `InkWell`
  opening `showWikiPicker` when the project has more than one wiki; a branch pill for code wikis;
  `HomeViewSwitch(wiki)` rightmost; **no compact action** (the three-segment pill leaves ~84 dp).
  Body `SafeArea(top:false,bottom:false)` → `RefreshIndicator` → `ContentColumn` → one
  `CustomScrollView`: Recent strip, then the tree rows (indent, chevron, title, non-conformant
  greyed). Empty states: no wiki ("This project has no wiki", Open on web), empty wiki. From the
  medium breakpoint the body is the list+detail Row with `WikiPageView(embedded: true)` (K6).
- `wiki_page_page.dart` (route outside the shell, like `workItemStandalone`) hosting
  `WikiPageView`: app bar per K9, body cache-first with the "Updated N min ago" line, `WikiMarkdown`
  inside a `SelectionArea`, find-in-page bar (K4), the K9 footer. Link routing: wiki-relative or
  same-wiki web URL → push another page; `#anchor` → scroll; `#id`/`!id`/`@<guid>` → the existing
  routes; `/.attachments/*` image → `AttachmentViewer`, file → share sheet; other `dev.azure.com`
  URLs → the app's route when one exists, else the browser; external → browser.
- `widgets/wiki_markdown.dart`: `MentionMarkdown`'s syntaxes plus a `wikiStyleSheet` (both themes,
  underlined links in `BoardhopColors.mention`, distinct h4–h6), front matter stripped into a Tags
  row, `[[_TOC_]]`/`[[_TOSP_]]` block syntaxes, the `:::` fence family and ```` ```mermaid ```` →
  placeholder cards (K3), `pre` builder through `CodeHighlighter` with a fence-id alias map and a
  copy button, the K10 table builder, `<br>` and a small inline-HTML subset (`u/sup/sub/del/ins`,
  colour tags stripped to text), HTML blocks through the existing `HtmlWidget` path, images through
  the wiki repo with `=WxH` as a maximum and the lightbox, heading keys for anchors, GUID mentions
  batch-resolved through the identity lookup. Long pages: `MarkdownBody` up to ~100 KB, a
  `SuperListView`-backed body above it (a timing spike on a synthetic 200 KB page decides the
  threshold), "Load anyway" above 1 MB.
- `widgets/wiki_picker_sheet.dart`, `widgets/toc_sheet.dart`, `widgets/wiki_page_picker_sheet.dart`
  (the composer's K12 sheet: tree plus a search field over titles, inserting `[title](url)`).
- Composers: `CommentComposer`, `ThreadCard` and the diff `_ComposerView` take a `WikiPageSource?`
  (null hides the book button), the way `MentionSource` and `AttachmentSource` are passed.
- Related tab: `groupLinkRelations` gains a `wikiPage` kind (Wiki Page artifact links, title from
  the path, tap → the reader) and an `other` bucket for `Hyperlink`; the count includes them.
- Search: `SearchKind.wiki`, the grouped section and See-all page with paging, hit → the reader by
  wiki id and path.
- Diagnostics: `/diagnostics/wiki` probe with canned markdown covering every construct and a "Wiki
  API" token check on the Diagnostics page.

### 4.3 Router

`Routes.wiki(account, org, project, {wiki, path})` in the Home branch; `Routes.wikiPage(account,
org, project, wiki, {path, id, version, anchor})` outside the shell; `MentionMarkdown`/`RichTextView`
intercept wiki URLs before falling to the browser. `_bleedsUnderRail` and the dock unchanged.

## 5. Acceptance

1. Scratch wiki: the tree (depth 4, the non-conformant page greyed, the outside-`.order` page last),
   home on first visit, recents after reading, last path restored after a cold restart.
2. `/Boardhop/Constructs` renders every construct: TOC in place and in the sheet, front matter tags,
   the four placeholder kinds, table wrapping and panning, task list, `<br>` in cells, `<details>`,
   the attachment image (tap → viewer), highlighted code with copy, footnotes, escapes; `/Boardhop`
   renders the child-page list; `/Boardhop/Links` resolves every relative form and the anchor.
3. `#15545` and `!8334` in a page open the item and the PR; `@<guid>` shows the name.
4. Work item #15545's Related tab shows the Wiki Page link and opens the reader; a wiki URL pasted in
   a scratch comment opens the reader; the composer's book button inserts a link that posts and reads
   back tappable (scratch only).
5. Search: the wiki section on the Search page (project and All), a hit opens the page; find-in-page
   steps through hits.
6. Both simulators, both themes, xxxL, portrait and landscape, the iPad tree+page layout; the client
   wiki opened read-only for a large real page (performance, TOC, tables) with no client screenshots
   sent or referenced.
7. Diagnostics: the Wiki API check ACCEPTED; the probe draws every construct.
8. Offline by widget tests (Ethernet Mac); `flutter analyze` clean, suite green; walkthrough under
   `research/walkthroughs/`.

## 6. Out of v1

Editing (pages, attachments), Wiki Page relation writes from the Related tab, starring, whole-wiki
download, mermaid/KaTeX/video rendering, markdown inside HTML blocks, `<iframe>` outside `::: video`,
a typed `[[` trigger, code-wiki verification, view counts, page history beyond the last change.
