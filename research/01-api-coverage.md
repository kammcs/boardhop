# Azure DevOps Services REST API — Coverage Assessment for a Mobile App

**Document:** `research/01-api-coverage.md`
**Date:** 2026-09-10
**Target API version:** 7.1 (GA) with named `7.1-preview.N` / `7.2-preview.N` exceptions
**Product goal:** a phone + tablet app blending the Jira mobile and GitHub mobile experiences — browse repos and PRs, review PRs (diffs, comments, vote, complete), view boards/sprints/backlogs, create/edit/comment/manage work items, view pipeline runs.
**Sources:** Microsoft Learn REST reference and conceptual docs, plus the Azure DevOps DevBlog for deprecation and release timing. Every endpoint below was checked against a live doc page. Claims that could not be confirmed from official documentation are explicitly marked **unverified**.

---

## Executive Summary

### The short version

**The API surface is good enough to build this app.** Repos, pull requests, work items, boards, backlogs, sprints, pipelines, wiki and search are all covered by GA `7.1` endpoints with sensible contracts. Two of the three headline experiences — PR review and work item management — are fully achievable.

**Four things will shape the project more than anything in the endpoint tables:**

1. **Authentication is in the middle of a forced migration, and personal Microsoft accounts are currently stranded.** Azure DevOps OAuth stopped accepting new app registrations on 23 April 2025 and retires during 2026. The replacement, Microsoft Entra ID OAuth, works well for mobile (public client + PKCE via MSAL) — but Microsoft's own docs still state that *"Entra apps don't natively support Microsoft account (MSA) users for the Azure DevOps resource"* and recommend the now-closed platform for those users. **If your target audience includes personal-MSA organizations, this is a launch blocker, not a detail.**
2. **There is no notification inbox API and no push service.** Azure DevOps has nothing resembling GitHub's `/notifications`. Delivery is email or webhook only, there is no read/unread state, and there is no Microsoft-operated APNs/FCM relay. A GitHub-Mobile-style inbox must be synthesized, and real push requires your own backend plus service hooks that **a project administrator must enable per project**.
3. **There is no unified-diff endpoint.** Every diff-shaped API returns structured change entries — path, change type, blob SHAs — never hunk text. The PR review screen, the app's centrepiece, requires a client-side diff engine plus a blob cache. (The good news: blobs are content-addressed, so caching by SHA is trivially correct and very effective.)
4. **Throttling presents as a slow HTTP 200, not a 429.** Combined with the fact that a cross-organization "PRs assigned to me" list requires fanning out per project, this is the most likely source of a sluggish app.

### Coverage table

Status key: **Full** = GA endpoints cover the feature · **Partial** = achievable with caveats, extra calls, preview dependencies or undocumented shapes · **Gap** = no documented API.

| Feature | Endpoint(s) | Scope | Status |
|---|---|---|---|
| **Organizations, profile, projects, teams** |  |  |  |
| List user's organizations | `GET app.vssps.visualstudio.com/_apis/accounts?memberId=` `7.1` | `vso.profile` | Full |
| Current user profile | `GET app.vssps.visualstudio.com/_apis/profile/profiles/me` `7.1` | `vso.profile` | Full |
| List projects | `GET {org}/_apis/projects` `7.1` | `vso.project` | Full |
| List teams (org-wide "my teams") | `GET {org}/_apis/teams?$mine=true` **`7.1-preview.3`** | `vso.project` | Partial — preview only |
| Project avatar | `_links.avatar` / `getDefaultTeamImageUrl` | `vso.project` | Partial — no documented GET |
| **Work items** |  |  |  |
| Get / batch get | `GET .../wit/workitems/{id}`, `POST .../wit/workitemsbatch` `7.1` | `vso.work` | Full (200-id cap) |
| Create / update (JSON Patch) | `POST .../wit/workitems/${type}`, `PATCH .../wit/workitems/{id}` `7.1` | `vso.work_write` | Full |
| WIQL queries | `POST .../wit/wiql` `7.1` | `vso.work` | Full (IDs only; 20k silent truncation; no `$skip`) |
| Saved queries | `GET .../wit/queries[/{idOrPath}]` `7.1` | `vso.work` | Full |
| Comments (read/write/react) | `.../wit/workItems/{id}/comments` **`7.1-preview.4`** (reactions `7.1-preview.1`) | `vso.work` / `vso.work_write` | Partial — **never GA'd** |
| Attachments upload / download | `POST` / `GET .../wit/attachments` `7.1` | `vso.work_write` / `vso.work` | Full (60 MB; chunked protocol unverified) |
| Links and relations | `/relations/-` JSON Patch; `.../wit/workitemrelationtypes` `7.1` | `vso.work_write` | Full (artifact URI templates under-documented) |
| Types, fields, states, transitions | `.../wit/workitemtypes[/{type}][/states\|/fields]` `7.1` | `vso.work` | Full |
| @mentions | `data-vss-mention` (HTML) / `@<guid>` (Markdown) | — | Full — documented |
| History / updates | `.../wit/workItems/{id}/updates`, `/revisions` `7.1` | `vso.work` | Full (`/history` undocumented at 7.1) |
| "Assigned to me" | WIQL `@Me` | `vso.work` | Full |
| "My recent activity" | `GET {org}/_apis/work/accountmyworkrecentactivity` `7.1` | `vso.work` | Full (outbound activity only, unpaged) |
| **"Following" list** | — | — | **Gap** — no documented API |
| **Boards** |  |  |  |
| Board config (columns, rows, mappings) | `GET .../work/boards[/{id}]` `7.1` | `vso.work` | Full |
| Backlogs and backlog configuration | `GET .../work/backlogs`, `.../work/backlogconfiguration` `7.1` | `vso.work` | Full (IDs only; hydrate via batch) |
| Iterations, capacity, team settings | `.../work/teamsettings/iterations*`, `.../work/teamsettings` `7.1` | `vso.work` / `vso.work_write` | Full |
| Team field values (area paths) | `.../work/teamsettings/teamfieldvalues` `7.1` | `vso.work` | Full |
| **Move a card between columns** | `PATCH .../wit/workitems/{id}` on `WEF_{guid}_Kanban.Column` + `System.State` | `vso.work_write` | Partial — works, but auto-derivation is undocumented; send both |
| Move a task on the Taskboard | `PATCH .../work/taskboardworkitems/{iter}/{id}` `7.1` | `vso.work_write` | Full — clean first-class API |
| Reorder backlog / sprint | `PATCH .../work/workitemsorder`, `.../work/iterations/{id}/workitemsorder` `7.1` | `vso.work_write` | Full |
| Card field / style settings | `.../work/boards/{b}/cardsettings`, `/cardrulesettings` `7.1` | `vso.work` | Partial — **untyped `object`, no schema, no samples** |
| Swimlane rules · intra-column position · collapse state | — | — | **Gap** |
| **Git and pull requests** |  |  |  |
| Repos, refs, branches, commits | `.../git/repositories`, `/refs`, `/commits`, `/stats/branches` `7.1` | `vso.code` | Full |
| File content and tree | `.../git/.../items`, `/itemsbatch`, `/blobs/{sha}`, `/trees/{sha}` `7.1` | `vso.code` | Full (no paging on Items) |
| PR list / get / create / update | `.../git/.../pullrequests` `7.1` | `vso.code` / `vso.code_write` | Full (description truncated to 400 in lists) |
| Complete / abandon / auto-complete | `PATCH .../pullrequests/{id}` `7.1` | `vso.code_write` | Full (`lastMergeSourceCommit` required) |
| Reviewers and votes | `PUT .../pullRequests/{id}/reviewers/{id}` `7.1` | `vso.code_write` | Full (`isRequired` read-only) |
| Threads, line comments, likes | `.../pullRequests/{id}/threads`, `/comments`, `/likes` `7.1` | `vso.code` + **`vso.threads_full`** | Full |
| PR iterations and changed files | `.../pullRequests/{id}/iterations[/{n}/changes]` `7.1` | `vso.code` | Full |
| **PR diff (hunks)** | — fetch both blobs, diff client-side | `vso.code` | **Gap** — no unified-diff endpoint |
| PR commits, labels, work items, attachments | `.../pullRequests/{id}/{commits\|labels\|workitems\|attachments}` `7.1` | `vso.code` / `vso.code_write` | Full |
| PR statuses | `.../pullRequests/{id}/statuses` `7.1` | `vso.code_status` | Full |
| Policy evaluations | `GET .../policy/evaluations?artifactId=` **`7.1-preview.1`** | `vso.code` | Partial — preview; different artifactId shape |
| **Suggested reviewers** | — | — | **Gap** |
| **Org-wide PR inbox** | — fan out per project | `vso.code` | **Gap** — no org-level endpoint |
| **Pipelines** |  |  |  |
| List pipelines / runs | `.../pipelines`, `.../build/builds` `7.1` | `vso.build` | Full (use Build API for lists) |
| Run detail and stage/job tree | `GET .../build/builds/{id}/timeline` `7.1` | `vso.build` | Full |
| Logs (ranged, and signed URLs) | `.../build/builds/{id}/logs/{logId}`; `.../pipelines/.../logs?$expand=signedContent` `7.1` | `vso.build` | Full |
| Queue / cancel / retry stage | `POST .../pipelines/{id}/runs`; `PATCH .../builds/{id}`; `PATCH .../builds/{id}/stages/{ref}` `7.1` | `vso.build_execute` | Full |
| YAML approvals | `GET` / `PATCH .../pipelines/approvals` `7.1` | `vso.build_execute` or `vso.pipelineresources_use` | Partial — no pipeline context until `7.2-preview.2` |
| Classic release + approvals | `vsrm.dev.azure.com/.../release/*` `7.1` | `vso.release*` | Full |
| Environments / deployment history | `.../distributedtask/environments*` `7.1` | `vso.environment_manage` | Partial — manage-only scope |
| Checks | `.../pipelines/checks/configurations` **`7.1-preview.1`** | `vso.build` | Partial — preview |
| **Live log streaming** | — poll the timeline | — | **Gap** |
| **Notifications** |  |  |  |
| Manage subscriptions | `.../notification/subscriptions` `7.1` | `vso.notification_write` | Full (email delivery only) |
| Service hooks (webhooks) | `.../hooks/subscriptions` `7.1` | `vso.work`/`vso.code`/`vso.build` | Partial — **project admin required, per project** |
| Work item delta feed | `.../wit/reporting/workitemrevisions?continuationToken=` `7.1` | `vso.work` | Full — true watermark feed |
| PR delta feed | — poll + diff client-side | `vso.code` | **Gap** |
| **Notification inbox / read state** | — | — | **Gap — does not exist** |
| **Push notifications** | — build your own backend | — | **Gap — no Microsoft relay** |
| **Search** |  |  |  |
| Code search | `POST almsearch.dev.azure.com/.../codesearchresults` `7.1` | `vso.code` | Partial — **requires `ms.vss-code-search` extension**, Basic access |
| Work item search | `POST .../workitemsearchresults` `7.1` | `vso.work` | Full — no extension needed |
| Wiki search | `POST .../wikisearchresults` `7.1` | `vso.wiki` | Full |
| Result caps | — | — | Partial — **undocumented**; watch `infoCode 8` |
| **Wiki** |  |  |  |
| List wikis, get page (JSON or raw Markdown) | `.../wiki/wikis[/{id}/pages]` `7.1` | `vso.wiki` | Full — `Accept: text/plain` for raw |
| Create/update page, attachments, page stats | `PUT .../pages`, `PUT .../attachments`, `.../pages/{id}/stats` `7.1` | `vso.wiki_write` / `vso.wiki` | Full (ETag mismatch status undocumented) |
| Wiki page comments | — | — | **Gap** — client-only, not in REST reference |
| **Identity and avatars** |  |  |  |
| People picker / user search | `POST .../graph/subjectquery` **`7.1-preview.1`**; `GET .../identities?searchFilter=` `7.1` | `vso.graph` / `vso.identity` | Full (subjectquery caps at 100, no paging) |
| Assignable users for a field | `GET .../wit/workitemtypes/{t}/fields/{f}?$expand=All` `7.1` | `vso.work` | Full |
| GUID ↔ descriptor | `.../graph/descriptors/{key}`, `.../graph/storagekeys/{desc}` `7.1` | `vso.graph` | Full |
| **Avatars** | `.../graph/Subjects/{desc}/avatars` `7.1`; `_links.avatar.href` | `vso.graph` | Partial — **auth behaviour undocumented; fetch via authenticated client** |
| **Cross-cutting** |  |  |  |
| Auth for mobile | Entra ID public client + PKCE (MSAL), resource `499b84ac-…` | delegated `vso.*` | Partial — **MSA users unsupported** |
| Rate limits | 200 TSTU / 5-min sliding window; `X-RateLimit-*`, `Retry-After` | — | Full — but throttling looks like a slow 200 |
| Pagination | `X-MS-ContinuationToken` header, or `$top`/`$skip` | — | Partial — inconsistent; page sizes undocumented |
| Batching | `workitemsbatch` (200), `itemsbatch`, `commitsbatch`, `pagesbatch` | — | Full — no global `$batch` |
| HTML fields + embedded images | `_apis/wit/attachments/{guid}` needs `Authorization` | `vso.work` | Partial — **WebView cannot load them; intercept or inline** |
| Markdown in fields | `/multilineFieldsFormat/{field}` JSON Patch; `WorkItem.multilineFieldsFormat` | `vso.work_write` | Partial — **read shape only in `7.2-preview.1`** |
| Markdown in comments | `format=markdown` + `$expand=renderedText` | `vso.work` | Full |
| On-premises parity | `7.1` = ADS 2022.1+; base `{server}:8080/tfs/{collection}` | — | Partial — **no OAuth on-prem**; no Accounts/Profile/Graph |

### Verification note

Microsoft's REST reference does **not** document the `multilineFieldsFormat` mechanism on any `wit/work-items` page. It is confirmed from two other first-party sources — the July 2025 release blog (which gives the JSON Patch path) and the extension-SDK `WorkItem` type reference (which gives the read shape) — and by diffing the `7.1` and `7.2-preview.1` schemas. It is treated as verified in this document, with the documentation gap noted, because a reader relying only on the REST reference would wrongly conclude that no such mechanism exists.

---

## 1. Organizations, Profile, Projects, Teams

### 1.1 Endpoints

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Current user profile | `GET https://app.vssps.visualstudio.com/_apis/profile/profiles/me?coreAttributes=Email,Avatar,DisplayName` | `7.1` | `vso.profile` |
| Orgs the user belongs to | `GET https://app.vssps.visualstudio.com/_apis/accounts?memberId={publicAlias}` | `7.1` | `vso.profile` |
| Resolve authenticated identity (alt.) | `GET https://dev.azure.com/{org}/_apis/connectionData` | *(not in REST reference)* | n/a |
| List projects | `GET https://dev.azure.com/{org}/_apis/projects?stateFilter=wellFormed&$top=&continuationToken=` | `7.1` | `vso.profile` or `vso.project` |
| Get project | `GET https://dev.azure.com/{org}/_apis/projects/{projectId}` | `7.1` | `vso.project` |
| Teams in a project | `GET https://dev.azure.com/{org}/_apis/projects/{projectId}/teams?$mine=true&$expandIdentity=` | `7.1` | `vso.project` |
| **All teams in org (my teams)** | `GET https://dev.azure.com/{org}/_apis/teams?$mine=true` | **`7.1-preview.3`** | `vso.project` |
| Team members | `GET https://dev.azure.com/{org}/_apis/projects/{projectId}/teams/{teamId}/members` | `7.1` | `vso.project` |
| Set / remove project avatar | `PUT` / `DELETE https://dev.azure.com/{org}/_apis/projects/{projectId}/avatar` | `7.1-preview.1` | `vso.project_write` |

### 1.2 The org-discovery handshake (mandatory first-run sequence)

Azure DevOps has **no "list my organizations" call on `dev.azure.com`**. The org list lives on a different host (`app.vssps.visualstudio.com`) and requires the caller's *profile* GUID, which you must fetch first:

```
1. GET https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1
   -> { "id": "d6245f20-...", "publicAlias": "d6245f20-...", "displayName": ..., "emailAddress": ... }

2. GET https://app.vssps.visualstudio.com/_apis/accounts?memberId={publicAlias}&api-version=7.1
   -> [ { accountId, accountName, accountUri }, ... ]     // accountName is the {org} segment

3. per org: GET https://dev.azure.com/{accountName}/_apis/projects?api-version=7.1
4. per project (or once, org-wide): GET https://dev.azure.com/{org}/_apis/teams?$mine=true&api-version=7.1-preview.3
```

`GET /_apis/accounts` **requires** `ownerId` or `memberId` — calling it bare returns an error. Use `publicAlias`, not `id`, when the two differ.

`GET https://dev.azure.com/{org}/_apis/connectionData` returns `authenticatedUser` / `authorizedUser` (identity GUID) plus `deploymentType` (`hosted` / `onPremises`) in a single unauthenticated-host-free call, and is the fastest way to get the identity GUID you need for `searchCriteria.reviewerId`, vote casting and `@Me`-style filters. **Caveat:** it is documented only as a TypeScript `ConnectionData` interface in the extension SDK reference and in support articles — it has **no page in the REST reference**. Treat it as semi-official.

### 1.3 Gaps and gotchas

- **`Teams - Get All Teams` is still `7.1-preview.3`** even under the 7.1 GA moniker. It is the only way to get "all my teams across the org" in one call, so a mobile app effectively must take a preview dependency here or fan out per project.
- **`continuationToken` on Projects–List is an integer offset** ("Pointer that shows how many projects already been fetched"), not the opaque string token used elsewhere in the platform. Do not write one generic pager for both shapes.
- **No documented GET for a project avatar.** Only `PUT`/`DELETE` exist. Read the image URL from the project's `_links.avatar.href`, or pass `getDefaultTeamImageUrl=true` to Projects–List and use `defaultTeamImageUrl`.
- Cross-host token audience: `app.vssps.visualstudio.com`, `dev.azure.com`, `vssps.dev.azure.com`, `vsrm.dev.azure.com`, `almsearch.dev.azure.com`, `vstmr.dev.azure.com` and `analytics.dev.azure.com` are **seven distinct hosts**. The same bearer token works across them, but your HTTP layer must not assume one base URL.

**Citations**
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/account/accounts/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/profile/profiles/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/core/projects/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/core/teams/get-teams?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/core/teams/get-all-teams?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/core/avatar/set-project-avatar?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/javascript/api/azure-devops-extension-api/connectiondata>

---

## 2. Work Items

Host `https://dev.azure.com/{org}`. Read = `vso.work`; create/update = `vso.work_write`. Note that **no WIT operation page lists `vso.work_full`** — even Delete and Recycle-Bin destroy document only `vso.work_write`. Treat `vso.work_full` as unnecessary for this app (*unverified* at operation level).

### 2.1 Read

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Get work item | `GET /{org}/{project}/_apis/wit/workitems/{id}?$expand=all&asOf=` | `7.1` | `vso.work` |
| Get many by id | `GET /{org}/{project}/_apis/wit/workitems?ids={csv}&fields=&errorPolicy=omit` | `7.1` | `vso.work` |
| **Batch get (preferred)** | `POST /{org}/{project}/_apis/wit/workitemsbatch` | `7.1` | `vso.work` |
| Updates (field deltas) | `GET /{org}/{project}/_apis/wit/workItems/{id}/updates?$top=&$skip=` | `7.1` | `vso.work` |
| Revisions (full snapshots) | `GET /{org}/{project}/_apis/wit/workItems/{id}/revisions` | `7.1` | `vso.work` |

`$expand` (`WorkItemExpand`): `none | relations | fields | links | all`.
Batch body: `{ ids, fields, $expand, asOf, errorPolicy }`, `errorPolicy` is `fail` or `omit`.

**Hard cap: 200 ids** on both `workitemsbatch` and `?ids=`. Prefer the POST — the GET also risks URL-length limits at 200 ids. Always pass an explicit `fields` allow-list and `errorPolicy: omit` so one deleted or inaccessible id does not fail the whole batch.

**Version note:** the `WorkItem` schema at `7.2-preview.1` contains a `multilineFieldsFormat` property that is **absent from the 7.1 schema**. See §10.4 — this is the one concrete reason to pin 7.2-preview on the work-item read path.

### 2.2 Create / update / delete (JSON Patch)

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Create | `POST /{org}/{project}/_apis/wit/workitems/${type}` | `7.1` | `vso.work_write` |
| Update | `PATCH /{org}/{project}/_apis/wit/workitems/{id}` | `7.1` | `vso.work_write` |
| Delete (to Recycle Bin) | `DELETE /{org}/{project}/_apis/wit/workitems/{id}?destroy=false` | `7.1` | `vso.work_write` |

- **`Content-Type: application/json-patch+json` is mandatory.** Sending `application/json` fails.
- The **literal `$`** precedes the type in the create path: `.../workitems/$Bug`, `.../workitems/$User%20Story`. URL-encode spaces; do **not** encode the `$`.
- Ops: `add`, `remove`, `replace`, `move`, `copy`, `test`. Fields at `/fields/{refName}`; relations appended at `/relations/-`, removed at `/relations/{index}` (positional — re-read first, and send removals in descending index order).
- Optimistic concurrency: prepend `{"op":"test","path":"/rev","value":N}`. **Use this on every mobile write** — stale state is the norm on a phone.
- Query flags: `validateOnly` (dry-run, excellent for validating a drag-and-drop before committing), `bypassRules` (needs elevated membership; exactly which is *unverified*), `suppressNotifications`, `$expand`.

```jsonc
PATCH https://dev.azure.com/{org}/{project}/_apis/wit/workitems/299?api-version=7.1
Content-Type: application/json-patch+json
[
  { "op": "test", "path": "/rev", "value": 12 },
  { "op": "add",  "path": "/fields/System.State", "value": "Active" },
  { "op": "add",  "path": "/fields/System.AssignedTo", "value": "user@contoso.com" },
  { "op": "add",  "path": "/relations/-",
    "value": { "rel": "System.LinkTypes.Hierarchy-Reverse",
               "url": "https://dev.azure.com/{org}/_apis/wit/workItems/297" } }
]
```

### 2.3 WIQL and saved queries

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Run WIQL | `POST /{org}/{project}/{team}/_apis/wit/wiql?$top=&timePrecision=` | `7.1` | `vso.work` |
| Run saved query | `GET /{org}/{project}/{team}/_apis/wit/wiql/{queryId}` | `7.1` | `vso.work` |
| Query tree | `GET /{org}/{project}/_apis/wit/queries?$depth=2&$expand=wiql` | `7.1` | `vso.work` |
| Get query by id **or path** | `GET /{org}/{project}/_apis/wit/queries/{queryIdOrPath}` | `7.1` | `vso.work` |

- **WIQL returns IDs only**, regardless of the SELECT list — the syntax doc states this explicitly. Always follow with `workitemsbatch` in chunks of 200 or fewer.
- **Results truncate silently at 20,000.** Query text max **32,000 characters**; execution timeout **30 s** on Services (6 minutes on-prem), error `VS402335`.
- **There is no `$skip` on the WIQL endpoint.** Paginate with `ORDER BY [System.Id]` plus a `WHERE [System.Id] > {lastId}` cursor.
- `{project}` is required for the `@Project` macro; `{team}` is required for `@CurrentIteration` (or use `@CurrentIteration('[Project]\Team')`).
- Saved queries: `{query}` accepts a GUID **or a URL-encoded path** (`Shared%20Queries%2FWebsite%20team%2FAll%20Bugs`). `$depth` is the only pager — no `$top`, no continuation token. Roots are `My Queries` and `Shared Queries`.
- Microsoft's own integration best-practices page is blunt: *"Using queries and individual get work item calls is the top way to get rate limits enforced on your organization."* For bulk/background sync use the reporting APIs (`_apis/wit/reporting/workitemrevisions`, `.../workitemlinks`) instead of WIQL polling.

### 2.4 Comments — still preview

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List (paged) | `GET /{org}/{project}/_apis/wit/workItems/{id}/comments?$top=&continuationToken=&$expand=renderedText&order=desc` | **`7.1-preview.4`** | `vso.work` |
| Get one | `GET .../comments/{commentId}` | `7.1-preview.4` | `vso.work` |
| **Add (format-aware)** | `POST .../comments?format=markdown` | `7.1-preview.4` | `vso.work_write` |
| Update | `PATCH .../comments/{commentId}?format=` | `7.1-preview.4` | `vso.work_write` |
| Delete (soft) | `DELETE .../comments/{commentId}` | `7.1-preview.4` | `vso.work_write` |
| Reactions add / remove / list | `PUT` / `DELETE` / `GET .../comments/{commentId}/reactions[/{type}]` | **`7.1-preview.1`** | `vso.work_write` / `vso.work` |

- **The Comments API has never gone GA.** It is `7.1-preview.4` (CRUD) and `7.1-preview.1` (reactions); 7.2 is `7.2-preview.4` / `7.2-preview.1`. Per the platform versioning policy, a preview revision "can be deactivated after 12 weeks" once that version GAs — so pin the exact revision and monitor it. **This is the single largest version risk in the app**, because the discussion view is core to both the Jira and GitHub mobile experiences.
- `format` (`markdown` or `html`) is a **required query parameter** on the *Add Work Item Comment* / *Update Work Item Comment* operations. The older plain *Add Comment* operation has no `format` param and its server default is undocumented (*unverified*; empirically HTML on legacy orgs).
- Read `text` (raw, in the declared `format`) plus `renderedText` (HTML). **Request `$expand=renderedText` and render the server-produced HTML** — that way the client never has to reimplement Azure DevOps' Markdown dialect. (`renderedTextOnly` exists but the docs mark it as for internal data-provider optimization; avoid.)
- Reaction types: `like, dislike, heart, hooray, smile, confused`. Sort with `order=asc|desc`; page with `$top` + `continuationToken`.
- Delete is **soft** — the comment remains with `isDeleted: true`.
- **Comment cap: 1,000 comments per work item via REST** (the web UI can exceed it).
- **Legacy alternative that still works and is sometimes better:** `PATCH /fields/System.History`. HTML-only, and it burns a work-item revision (10,000-revision REST cap), but it is the *only* way to post a comment **atomically together with** a field change and a link in a single request. Every official Update sample uses it.

### 2.5 Attachments

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Upload | `POST /{org}/{project}/_apis/wit/attachments?fileName=&uploadType=simple&areaPath=` | `7.1` | `vso.work_write` |
| Download | `GET /{org}/{project}/_apis/wit/attachments/{id}?fileName=&download=true` | `7.1` | `vso.work` |

Upload with `Content-Type: application/octet-stream`; the `201` response carries `{ id, url }`. **Upload does not attach** — you must then JSON-Patch an `AttachedFile` relation, keeping `?fileName=` on the relation URL (that is what names it in the UI):

```jsonc
{ "op": "add", "path": "/relations/-",
  "value": { "rel": "AttachedFile",
             "url": "https://dev.azure.com/{org}/_apis/wit/attachments/{guid}?fileName=Spec.txt",
             "attributes": { "comment": "Spec for the work" } } }
```

Limits (object-limits page): **attachment size 60 MB**, **100 attachments per work item**. The API reference page separately mentions orgs with raised limits (">130MB") requiring chunked upload — the two pages disagree; enforce 60 MB client-side. **The chunked-upload protocol (chunk PUT shape, `Content-Range`, chunk size, finalize) is not specified on the 7.1 reference page — unverified.**

### 2.6 Relations and artifact links

`GET /{org}/_apis/wit/workitemrelationtypes` (18 types) and `GET /{org}/_apis/wit/artifactlinktypes`, both `7.1` / `vso.work`.

Key reference names: `System.LinkTypes.Hierarchy-Forward` (Child), `System.LinkTypes.Hierarchy-Reverse` (Parent), `System.LinkTypes.Dependency-Forward` (Successor) / `-Reverse` (Predecessor), `Microsoft.VSTS.Common.TestedBy-Forward` / `-Reverse`, and **`System.LinkTypes.Related`, which has no `-Forward`/`-Reverse` suffix** — a very common integration bug. Resource-link usages: `AttachedFile`, `Hyperlink`, `ArtifactLink`.

Artifact link to a pull request:

```jsonc
{ "op": "add", "path": "/relations/-",
  "value": { "rel": "ArtifactLink",
             "url": "vstfs:///Git/PullRequestId/{projectId}/{repositoryId}/{pullRequestId}",
             "attributes": { "name": "Pull Request" } } }
```

**Caveat:** that URI template is documented only on the **legacy TFS-2017 previous-versions page**; the current 7.1 reference never restates it. The Commit, Build and Branch templates are **not documented anywhere current — unverified**. Derive them at runtime from an existing item's `relations[].url`, or use `POST /_apis/wit/artifacturiquery`. The requirement that `attributes.name` match the `linkType` string from `artifactlinktypes` is also *unverified*.

Limit: **1,000 links per work item**.

**Removal is positional and unguarded (spikes s35/s36, 2026-09-12).** `remove /relations/{index}` takes the
index of the relation in the item's own `relations[]`, so the indices must come from a read made immediately
before the patch and several removals must be sent in **descending** index order. `test /rev` does not protect
that patch: a **relation-only patch creates no new revision** — adding and removing a `System.LinkTypes.Related`
link left `rev` at 1 and `System.ChangedDate` untouched — although adding an `AttachedFile` did bump both.
`System.AttachedFileCount`, `System.RelatedLinkCount` and `System.ExternalLinkCount` are **not returned by the
item read**, not even with `$expand=all`, so a count comes from the relations themselves.

A relation also cannot be identified by its URL: the service **rewrites it with the project GUID** and drops the `?fileName=` query (spike s37), so the caller must match on the target id or the attachment guid instead of the URL it sent. A `PATCH` answers without `relations[]` unless `$expand=relations` is on it.

### 2.7 Types, fields, states, transitions

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Work item types | `GET /{org}/{project}/_apis/wit/workitemtypes[/{type}]` | `7.1` | `vso.work` |
| States (+ colors, categories) | `GET /{org}/{project}/_apis/wit/workitemtypes/{type}/states` | `7.1` | `vso.work` |
| Fields for a type | `GET /{org}/{project}/_apis/wit/workitemtypes/{type}/fields` | `7.1` | `vso.work` |
| All fields | `GET /{org}/{project}/_apis/wit/fields?$expand=` | `7.1` | `vso.work` |
| Type categories | `GET /{org}/{project}/_apis/wit/workitemtypecategories` | `7.1` | `vso.work` |
| Process types / form layout | `GET /{org}/_apis/work/processes/{processId}/workitemtypes?$expand=layout` | `7.1` | `vso.work` |

- **`GET workitemtypes/{type}` is the only place you get legal state transitions.** It returns `transitions` as a map `fromState -> [{ to, actions }]`, with `""` as the pseudo-initial state. The `/states` endpoint returns only name, color and `category` (`Proposed`, `InProgress`, `Resolved`, `Completed`, `Removed`). **Drive the mobile state picker from `transitions`, not from the flat state list**, or users will be offered illegal transitions that fail on save.
- `WorkItemType` also gives `color` (`"CC293D"`) and `icon` (`{ id: "icon_insect", url }`) — everything a card renderer needs. **Strip `xmlForm` before caching; it is enormous.**
- Filter `Microsoft.HiddenCategory` out of any "new work item" type picker.
- Field-count limits are inconsistent between doc pages (64 custom fields per WIT on one, 1024 fields per WIT on another). Do not hard-code either.

### 2.8 @mentions — verified

From the official at-mentions doc, the syntax **depends on which editor produced the content**:

- **HTML editor:** `<a href="#" data-vss-mention="version:2.0,{userGUID}">@John Doe</a>`
- **Markdown editor:** `@<userGUID>` (angle brackets literal)

So post the form that matches the `format` you are writing with, and make the **renderer handle both**. The GUID is any `IdentityRef.id` you already hold (`System.AssignedTo.id`, `comment.createdBy.id`) or a Graph user id. Parsed mentions come back in `comment.mentions[]` with `artifactType: "person"` and a resolved `targetId`, so you can render display names without extra Graph calls. The doc warns that copy-pasting a rendered mention from another comment does **not** register a real mention and sends no notification — worth surfacing as in-app guidance.

@mentions work in work item discussions and any rich-text field, PR discussions, commit and changeset comments, and wiki page comments.

### 2.9 "My work" surfaces

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| **My recent activity** | `GET /{org}/_apis/work/accountmyworkrecentactivity` | `7.1` (GA) | `vso.work` |
| Recycle bin list / restore / destroy | `GET` / `PATCH` (`{"isDeleted":false}`) / `DELETE /{org}/{project}/_apis/wit/recyclebin[/{id}]` | `7.1` | `vso.work` / `vso.work_write` |

- `accountmyworkrecentactivity` is **org-scoped, GA and cheap** — the best home-screen feed. Returns `{ id, title, workItemType, state, teamProject, assignedTo, changedDate, activityDate, activityType }` where `activityType` is `visited`, `edited`, `deleted` or `restored`. Note it lives under `_apis/work/`, not `_apis/wit/`, and takes **no paging parameters**.
- **"Assigned to me"** has no dedicated endpoint — use WIQL with the `@Me` macro, then hydrate via batch.
- **"Following" is a genuine gap** — see §2.10.
- The resource path is **`recyclebin`** (one word); `/wit/recycle-bin/` 404s.

### 2.10 Gaps and limitations

1. **No Follow/unfollow API.** There is no documented `follows` endpoint at any api-version. Following is internally a personal notification subscription, but the mapping is undocumented. **A "Following" tab cannot be built reliably. Gap.**
2. **Comments API is permanently preview** (`7.1-preview.4`) — the core of any mobile discussion UI rests on a preview contract.
3. **`accountmyworkrecentmentions` does not exist** in the 7.1/7.2 reference. Do not build on it.
4. **`multilineFieldsFormat` is absent from the 7.1 `WorkItem` schema** — at 7.1 you cannot tell whether `System.Description` is HTML or Markdown. See §10.4.
5. Chunked attachment upload mechanics unspecified (*unverified*).
6. Attachment download requires the `Authorization` header — it is a normal `_apis` route, not a pre-signed URL. (Inferred from the declared `vso.work` scope; *not stated explicitly*.) This is the root of the embedded-image problem in §10.3.
7. `GET .../workItems/{id}/history` is still emitted in `_links.workItemHistory` but has **no 7.1 reference page**. Use `/updates` plus `/revisions`. ("Deprecated" is an inference — *unverified*.)
8. Work-item `$batch` (`PATCH /{org}/_apis/wit/$batch`) is documented **only at `api-version=6.1`** on a conceptual page, with no generated reference page and no documented item cap. *Unverified at 7.1.*
9. Caps to design around: **200** ids per batch, **20,000** WIQL results (silent truncation), **10,000** REST revisions per work item, **1,000** comments per work item via REST, **1,000** links, **100** tags, **1,000,000** characters per long-text field.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/get-work-items-batch?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/get-work-items-batch?view=azure-devops-rest-7.2>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/wiql/query-by-wiql?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/queries/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/comments/get-comment?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/comments/add-work-item-comment?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-relation-types/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-types/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/account-my-work-recent-activity/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/organizations/notifications/at-mentions?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/boards/queries/wiql-syntax?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/integration-bestpractices?view=azure-devops>

---

## 3. Boards, Backlogs, Sprints

All Work-area endpoints are **GA at plain `7.1`**. The 7.2 contracts for `Board`, `BoardColumn`, `BoardRow` and `BoardFields` are byte-identical to 7.1, so **there is no reason to take a preview dependency in this area**. Base shape: `https://dev.azure.com/{org}/{project}/{team}/_apis/work/...` — `{team}` is optional on most board endpoints (falls back to the project's default team) but **required** on `backlogs/*`, `workitemsorder/*`, `taskboardcolumns` and `taskboardworkitems`.

### 3.1 Boards

| Capability | Method + Path (after `{org}/{project}/{team}/_apis/work/`) | api-version | Scope |
|---|---|---|---|
| List boards | `GET boards` | `7.1` | `vso.work` |
| Get board (columns, rows, fields) | `GET boards/{id}` | `7.1` | `vso.work` |
| Columns get / update | `GET` / `PUT boards/{board}/columns` | `7.1` | `vso.work` / `vso.work_write` |
| Rows (swimlanes) get / update | `GET` / `PUT boards/{board}/rows` | `7.1` | `vso.work` / `vso.work_write` |
| Card field settings | `GET` / `PUT boards/{board}/cardsettings` | `7.1` | `vso.work` / `vso.work_write` |
| Card style rules | `GET` / `PATCH boards/{board}/cardrulesettings` | `7.1` | `vso.work` / `vso.work_write` |
| Per-user board settings | `GET` / `PATCH boards/{board}/boardusersettings` | `7.1` | `vso.work` / `vso.work_write` |
| Board charts | `GET boards/{board}/charts[/{name}]` | `7.1` | `vso.work` |
| Board parents | `GET boards/boardparents?childBacklogContextCategoryRefName=&workitemIds=` | `7.1` | `vso.work` |

`{id}` / `{board}` accepts **either the board GUID or the backlog level name** (`"Stories"`, `"Epics"`).

`Board` returns: `columns[]`, `rows[]`, `fields`, `allowedMappings`, **`canEdit`**, **`isValid`**, `revision`. Gate all write affordances on `canEdit && isValid`.

`BoardColumn`: `id`, `name`, `itemLimit` (WIP limit; `0` = none), `stateMappings` (map of work item type to state), `columnType` (`incoming | inProgress | outgoing`), `isSplit`, `description` (the Definition of Done text).
`BoardRow`: `id`, `name`, `color`. The default swimlane is `id = "00000000-0000-0000-0000-000000000000"` with `name: null`.

### 3.2 Backlogs and backlog configuration

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List backlog levels | `GET {org}/{project}/{team}/_apis/work/backlogs` | `7.1` | `vso.work` |
| Work items at a level | `GET .../backlogs/{backlogId}/workItems` | `7.1` | `vso.work` |
| **Backlog configuration** | `GET .../_apis/work/backlogconfiguration` | `7.1` | `vso.work` |
| Process configuration | `GET {org}/{project}/_apis/work/processconfiguration` | `7.1` | `vso.work` |

`backlogId` is a category reference name: `Microsoft.EpicCategory`, `Microsoft.FeatureCategory`, `Microsoft.RequirementCategory`, `Microsoft.TaskCategory`.

**`backlogconfiguration` is the single most valuable bootstrap call** — one round trip returns the whole taxonomy: `portfolioBacklogs[]`, `requirementBacklog`, `taskBacklog`, `hiddenBacklogs[]`, `bugsBehavior` (`off | asRequirements | asTasks`), `backlogFields.typeFields` (which tells you the real reference name for `Order`, `Effort`, `RemainingWork`, `Activity` — **read these, never hard-code `Microsoft.VSTS.Common.StackRank`**, since Agile/Scrum/CMMI/custom processes differ), and `workItemTypeMappedStates[]` mapping each state to a state *category*.

**Gotcha:** `GET backlogs/{backlogId}/workItems` returns **IDs and hierarchy links only** — no fields, no documented ordering, no paging. Always follow with `POST _apis/wit/workitemsbatch`.

### 3.3 Iterations, capacity, team settings

| Capability | Method + Path (after `{org}/{project}/{team}/_apis/work/`) | api-version | Scope |
|---|---|---|---|
| Team iterations | `GET teamsettings/iterations?$timeframe=current` | `7.1` | `vso.work` |
| Iteration work items | `GET teamsettings/iterations/{iterationId}/workitems` | `7.1` | `vso.work` |
| Capacities (with totals) | `GET teamsettings/iterations/{iterationId}/capacities` | `7.1` | `vso.work` |
| Replace / update capacity | `PUT` / `PATCH teamsettings/iterations/{iterationId}/capacities[/{memberId}]` | `7.1` | `vso.work_write` |
| Team days off | `GET` / `PATCH teamsettings/iterations/{iterationId}/teamdaysoff` | `7.1` | `vso.work` / `vso.work_write` |
| Team settings | `GET` / `PATCH teamsettings` | `7.1` | `vso.work` / `vso.work_write` |
| Team field values (area paths) | `GET` / `PATCH teamsettings/teamfieldvalues` | `7.1` | `vso.work` / `vso.work_write` |
| Areas / iterations tree | `GET {org}/{project}/_apis/wit/classificationnodes/{areas\|iterations}/{path}?$depth=` | `7.1` | `vso.work` |

**Gotchas that will bite a mobile client:**
- `$timeframe` is documented as **"Only `Current` is supported currently."** Enumerate all iterations and filter client-side on `attributes.timeFrame`.
- Iteration `startDate` / `finishDate` can be **`null`** — a sprint with no dates is legal. Dates are "date-only, correct unadjusted at midnight in UTC": **do not apply a local timezone shift**, or sprint boundaries drift by a day.
- The `Iterations – List` sample wraps results in **`"values"`**, not `"value"` — inconsistent with every other list endpoint. Parse defensively for both.
- `Get Iteration Work Items` uses the property name `workItemRelations`, while the backlog equivalent uses `workItems`. Different shapes for the same idea.
- On classification nodes, the node has both `id` (int32) and `identifier` (uuid). **`identifier` is the one that matches `TeamSettingsIteration.id`** — a classic bug source. Note it lives under `_apis/wit/`, not `_apis/work/`.

### 3.4 Moving a card between Kanban columns

This is the highest-risk interaction in the whole Boards surface, so it is worth being precise.

**There are two families of board fields, and confusing them is the number-one integration bug.**

| Family | Reference name | Writable |
|---|---|---|
| Per-team board fields | `WEF_{BoardGuid}_Kanban.Column` | **Yes — this is what you PATCH** |
| | `WEF_{BoardGuid}_Kanban.Column.Done` | Yes (boolean) |
| | `WEF_{BoardGuid}_Kanban.Lane` | Yes |
| Aggregate query fields | `System.BoardColumn`, `System.BoardColumnDone`, `System.BoardLane` | **No — read-only** |

The docs state plainly: *"Even if you add a board-related field, such as Board Column or Board Lane, to a work item form, you can't modify the field from the form."* And critically for multi-team projects: *"the team with the longest area path takes precedence in resolving conflicts and determines the values for the Board Column, Board Column Done, and Board Lane fields."* **Always read and write the `WEF_` field for *your* board**, never `System.BoardColumn`, or cards will appear to jump columns when another team moves them.

**Discover the field names; never synthesize them.** `GET .../_apis/work/boards/{id}` returns:

```jsonc
"fields": {
  "columnField": { "referenceName": "WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Column" },
  "doneField":   { "referenceName": "WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Column.Done" },
  "rowField":    { "referenceName": "WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Lane" }
}
```

Only the `_Kanban.Column` form is attested verbatim in official docs (in a service-hook payload sample). That the GUID equals `Board.id` uppercased with dashes stripped is an **inference — unverified**. The `fields` object is the documented, supported discovery mechanism; use it.

**Does writing the column field auto-derive `System.State`? Not documented, either way.** Contrast with the Taskboard, where auto-derivation *is* documented (`TaskboardColumn.mappings` — *"to support auto state update when column is updated"*). **No equivalent sentence exists for the Kanban board.** The safe design is to send both in one atomic patch — correct under either server behaviour, and it avoids a torn intermediate state.

When you must also change state, derive it from `targetColumn.stateMappings[workItemType]`:

| Situation | Action |
|---|---|
| Target column maps to a different state | Set column **and** `System.State` |
| Two adjacent columns map to the same state | Column only; leave state alone |
| Doing to Done within a split column | Only the `.Column.Done` boolean changes |
| Moving into a non-split column | Omit the `.Column.Done` op entirely |
| Target state absent from `stateMappings[wit]` | Illegal move for that type — reject client-side |

**The move:**

```jsonc
PATCH https://dev.azure.com/{org}/{project}/_apis/wit/workitems/299?api-version=7.1
Content-Type: application/json-patch+json
[
  { "op": "test", "path": "/rev", "value": 12 },
  { "op": "add",  "path": "/fields/WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Column",      "value": "Committed" },
  { "op": "add",  "path": "/fields/WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Column.Done", "value": false },
  { "op": "add",  "path": "/fields/System.State", "value": "Committed" },
  { "op": "add",  "path": "/fields/WEF_6CB513B6E70E43499D9FC94E5BBFB784_Kanban.Lane",        "value": "Expedite" }
]
```

The column field stores the column **name**, not its GUID. For the default swimlane the row name is `null` — **omit the lane op rather than sending `null`**. Use `validateOnly=true` to dry-run a drag before committing.

**The Sprint Taskboard has a clean first-class move API that the Kanban board lacks:**

```
PATCH {org}/{project}/{team}/_apis/work/taskboardworkitems/{iterationId}/{workItemId}?api-version=7.1
{ "newColumn": "In Progress" }
```
Returns `200` with no body, and updates state automatically per `TaskboardColumns.columns[].mappings`. Use it for sprint task drag-and-drop.

### 3.5 Reordering (backlog and intra-column)

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| Reorder backlog / board items | `PATCH {org}/{project}/{team}/_apis/work/workitemsorder` | `7.1` | `vso.work_write` |
| Reorder iteration items | `PATCH {org}/{project}/{team}/_apis/work/iterations/{iterationId}/workitemsorder` | `7.1` | `vso.work_write` |

**Path trap:** the reorder route is `_apis/work/**iterations**/{id}/workitemsorder` — *not* `_apis/work/teamsettings/iterations/...` which every other iteration endpoint uses. `{team}` is required on both.

Body: `{ ids: [int], previousId, nextId, parentId, iterationPath }`, where `previousId: 0` means "start of list", `nextId: 0` means "end of list", `parentId: 0` means "no parent".

**Gotcha:** the response `ReorderResult[]` may contain **more entries than you sent** — the server renormalizes and returns neighbours too. Do not assume `response.value.length === ids.length`; re-apply every returned `order` value to your local model.

### 3.6 Can a mobile app reconstruct the Kanban board? Mostly yes

| Board element | Source | Fidelity |
|---|---|---|
| Columns, order, names | `Board.columns[]` | Full |
| WIP limits | `BoardColumn.itemLimit` | Full |
| Split columns | `BoardColumn.isSplit` + `doneField` | Full |
| Definition of Done text | `BoardColumn.description` | Full |
| Swimlanes and colors | `Board.rows[]` | Full |
| Card placement | `WEF_` fields via WIQL or batch | Full |
| Column to state mapping | `BoardColumn.stateMappings` | Full |
| Work item type colors and icons | `_apis/wit/workitemtypes` | Full (extra call) |
| **Card field list** | `cardsettings.cards` | **Untyped `object`** |
| **Card style / tag-color rules** | `cardrulesettings.rules` | **Untyped `object`** |

### 3.7 Gaps and limitations

1. **`BoardCardSettings.cards` and `BoardCardRuleSettings.rules` are declared as bare `object` with no schema and no sample JSON on any of the four reference pages.** To render card fields, fill colours and tag colours faithfully you must reverse-engineer from a live response and pin to it. **This is the single biggest fidelity risk in the Boards area.**
2. **No swimlane-rule API.** Swimlane auto-routing rules exist in the product but are not exposed. A card dragged into a rule-managed lane may be bounced by the server and your client cannot predict it.
3. **No card-reordering-mode API**, and under "allow free reordering within columns" there is **no documented way to set a card's position within a column**.
4. **`BoardUserSettings` contains only `autoRefreshState`** — it does *not* carry column/swimlane collapse state. Store that locally on device.
5. **No board-level "get all cards" endpoint.** There is no `boards/{id}/cards`. Expect two to three round trips before first paint.
6. **`allowedMappings` is untyped.**
7. **`Set Board Options` (`PUT boards/{id}`) has no documented request body and no response schema.** Avoid.
8. **No ETag/If-Match concurrency contract for board configuration.** `Board.revision` exists but the protocol is unspecified. For work items, `{"op":"test","path":"/rev"}` *is* documented — use it.
9. Board object limits: **1,000 cards per board**, 10,000 items in a backlog display.

**Suggested cold-start sequence** (six calls, all `vso.work`): `backlogconfiguration` → `teamsettings` → `backlogs` → `boards` → `boards/{id}` → `boards/{id}/cardsettings` + `/cardrulesettings`. Cache keyed on `Board.revision`. Then per view: backlog or iteration work-item IDs → `POST _apis/wit/workitemsbatch`.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/boards/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/columns/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/cardsettings/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/boardusersettings/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/backlogconfiguration/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/backlogs/get-backlog-level-work-items?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/iterations/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/teamsettings/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/workitemsorder/reorder-backlog-work-items?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/work/taskboard-work-items/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/boards/queries/query-by-workflow-changes?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/boards/boards/add-columns?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/boards/boards/customize-cards?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/service-hooks/services/trello?view=azure-devops>

---

## 4. Git: Repos and Pull Requests

Every Git operation is **GA at plain `7.1`**. The **only** preview endpoint in this whole area is Policy Evaluations (`7.1-preview.1`). Base: `https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repositoryId}/...`.

### 4.1 Repos, refs, commits, file content

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List repos (project or org-wide) | `GET /{org}[/{project}]/_apis/git/repositories` | `7.1` | `vso.code` |
| Get repo | `GET .../repositories/{repositoryId}` | `7.1` | `vso.code` |
| List refs | `GET .../refs?filter=heads/&filterContains=&includeStatuses=&latestStatusesOnly=&$top=&continuationToken=` | `7.1` | `vso.code` |
| Branch stats (ahead/behind) | `GET .../stats/branches[?name={branch}]` | `7.1` | `vso.code` |
| List commits | `GET .../commits?searchCriteria.*` | `7.1` | `vso.code` |
| Get commit / changes | `GET .../commits/{commitId}[/changes]` | `7.1` | `vso.code` |
| Commits batch | `POST .../commitsbatch` | `7.1` | `vso.code` |
| Get item (file/folder) | `GET .../items?path=&scopePath=&recursionLevel=&includeContent=&includeContentMetadata=&versionDescriptor.*` | `7.1` | `vso.code` |
| Items batch (metadata only) | `POST .../itemsbatch` | `7.1` | `vso.code` |
| **Get blob (raw bytes)** | `GET .../blobs/{sha1}?$format=text\|octetstream\|json\|zip` | `7.1` | `vso.code` |
| Get tree | `GET .../trees/{sha1}?recursive=true` | `7.1` | `vso.code` |

**Notable behaviours:**
- `filter` on refs is a **prefix match with `refs/` stripped** — `filter=heads/` for branches, `filter=tags/` for tags. `$top` cannot exceed **1000**; if `continuationToken` is supplied without `$top`, `$top` defaults to 100. `latestStatusesOnly=true` requires `includeStatuses=true`. `includeMyBranches` cannot be combined with `filter`.
- Commits: `searchCriteria.` may be dropped from any of its parameters (`$top` works as well as `searchCriteria.$top`). `ids` cannot be combined with other parameters. `author`/`user` match alias or display name, **not email** — fuzzy and brittle.
- **`Get commit changes` uses lowercase `top`/`skip`**, not `$top`/`$skip`. Easy bug.
- **Items:** for JSON-wrapped text use `includeContent=true&$format=json` (`GitItem.content` is a plain string, **not base64**). For raw text send `Accept: text/plain` with no `$format`. `$format=text`/`octetstream` are documented for **Blobs**, not Items (*partially unverified* for Items).
- **Blobs default to metadata only.** A bare `GET .../blobs/{sha}` returns `{ objectId, size, url }`. You must ask for `$format=text` or `$format=octetstream` to get bytes.
- **`itemsbatch` has no `includeContent` field** — it returns metadata only, and its response is an **array of arrays** (`value[n]` corresponds to `itemDescriptors[n]`). Use it to resolve blob SHAs and `contentMetadata` for many paths in one round trip.
- **Items and Items-List have no paging at all** — no `$top`, no continuation token. `recursionLevel=Full` on a large repo returns an unbounded payload. On mobile always use `OneLevel` and drill down. The scope folder itself is returned as the first entry; skip it.
- `contentMetadata` (via `includeContentMetadata=true`) gives `{ fileName, extension, contentType, encoding, isBinary, isImage }` — **this is your binary-detection signal**.
- Repo/file limits: repository ≤ **250 GB** (10 GB recommended), individual file ≤ **100 MB**, push ≤ 5 GB, path ≤ 32,766 chars. **No documented byte cap for REST item/blob downloads** — gate client-side on `GitBlobRef.size` / `GitTreeEntryRef.size`.

### 4.2 Pull requests

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List by repo | `GET .../repositories/{repositoryId}/pullrequests?searchCriteria.*&$top=&$skip=` | `7.1` | `vso.code` |
| List by project | `GET /{org}/{project}/_apis/git/pullrequests?searchCriteria.*` | `7.1` | `vso.code` |
| Get by id (repo-free) | `GET /{org}[/{project}]/_apis/git/pullrequests/{pullRequestId}` | `7.1` | `vso.code` |
| Get PR | `GET .../pullrequests/{id}?includeCommits=&includeWorkItemRefs=` | `7.1` | `vso.code` |
| Create | `POST .../pullrequests` | `7.1` | `vso.code_write` |
| Update (complete / abandon / auto-complete) | `PATCH .../pullrequests/{id}` | `7.1` | `vso.code_write` |
| Which PR contains a commit | `POST .../pullrequestquery` | `7.1` | `vso.code` |

`searchCriteria`: `.status` (**defaults to `active`** — pass `all` for history), `.creatorId` and `.reviewerId` (**GUIDs**, not emails), `.sourceRefName` / `.targetRefName` (full `refs/heads/x`), `.repositoryId`, `.sourceRepositoryId` (forks), `.minTime` / `.maxTime`, `.queryTimeRangeType` (`created` | `closed`), plus `$top` / `$skip`.

**`description` is truncated to 400 characters in both list APIs** — you must call Get PR for the detail screen. `maxCommentLength`, and `$top`/`$skip` on Get PR, are all documented as "Not used."

**Only these fields are patchable:** Status, Title, Description (≤4000 chars), CompletionOptions, MergeOptions, `AutoCompleteSetBy.Id`, and TargetRefName when retargeting is enabled. The docs warn that anything else *"will either cause the server to throw an `InvalidArgumentValueException`, or to silently ignore the update."* The silent-ignore case is the dangerous one — notably `isDraft` is **not** on the patchable list, so publishing a draft via PATCH is *unverified*.

**Complete a PR:**

```jsonc
PATCH .../pullrequests/{id}?api-version=7.1
{
  "status": "completed",
  "lastMergeSourceCommit": { "commitId": "<pr.lastMergeSourceCommit.commitId>" },
  "completionOptions": {
    "mergeStrategy": "squash",          // noFastForward | squash | rebase | rebaseMerge
    "deleteSourceBranch": true,
    "transitionWorkItems": true,
    "mergeCommitMessage": "Merged PR 22: ...",
    "bypassPolicy": false
  }
}
```

- **`lastMergeSourceCommit` is required** — it is the optimistic-concurrency guard. Re-GET the PR immediately before completing and echo the value back, or you race a concurrent push.
- **`squashMerge` is deprecated**: *"If MergeStrategy is set to any value, the SquashMerge value will be ignored."* Always set `mergeStrategy` explicitly.
- Abandon: `{"status":"abandoned"}`. Reactivate: `{"status":"active"}`. Set auto-complete: `{"autoCompleteSetBy":{"id":"<guid>"}}`. Clearing auto-complete with the null GUID is *unverified*.
- `autoCompleteIgnoreConfigIds` applies **only to non-blocking (optional) policies**.

### 4.3 Reviewers and votes

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List / get reviewers | `GET .../pullRequests/{id}/reviewers[/{reviewerId}]` | `7.1` | `vso.code` |
| **Cast vote / add reviewer** | `PUT .../pullRequests/{id}/reviewers/{reviewerId}` | `7.1` | `vso.code_write` |
| Add reviewers (batch) | `POST .../pullRequests/{id}/reviewers` | `7.1` | `vso.code_write` |
| Remove reviewer | `DELETE .../pullRequests/{id}/reviewers/{reviewerId}` | `7.1` | `vso.code_write` |
| Flag / decline | `PATCH .../pullRequests/{id}/reviewers/{reviewerId}` | `7.1` | `vso.code_write` |
| Notify reviewers by email | `POST .../pullRequests/{id}/share` | `7.1` | `vso.code_write` |

**Vote values:** `10` Approved · `5` Approved with suggestions · `0` No vote / reset · `-5` Waiting for author · `-10` Rejected.

The primary approve action is simply a `PUT` of yourself as the reviewer:

```jsonc
PUT .../pullRequests/22/reviewers/{myIdentityGuid}?api-version=7.1
{ "vote": 10, "id": "{myIdentityGuid}" }
```

- **`isRequired` is read-only here** — required reviewers come from branch policy. Render the badge; do not try to set it.
- `isFlagged` and `hasDeclined` *are* patchable via the `PATCH` reviewer operation.
- `isReapprove` re-fires the vote event when re-approving after a new push without a vote value change.
- **Groups and teams can be reviewers but cannot vote directly** — a member's vote rolls up via `votedFor[]`. Your UI must handle `isContainer: true` reviewers.

### 4.4 Threads and comments

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List / get threads | `GET .../pullRequests/{id}/threads[/{threadId}]?$iteration=&$baseIteration=` | `7.1` | `vso.code` or `vso.threads_full` |
| Create thread | `POST .../pullRequests/{id}/threads` | `7.1` | `vso.code_write` or `vso.threads_full` |
| Update thread status | `PATCH .../pullRequests/{id}/threads/{threadId}` | `7.1` | `vso.code_write` / `vso.threads_full` |
| Reply | `POST .../threads/{threadId}/comments` | `7.1` | `vso.code_write` / `vso.threads_full` |
| Edit / delete comment | `PATCH` / `DELETE .../threads/{threadId}/comments/{commentId}` | `7.1` | `vso.code_write` / `vso.threads_full` |
| **Like / unlike** | `POST` / `DELETE .../threads/{threadId}/comments/{commentId}/likes` | `7.1` | `vso.code_write` / `vso.threads_full` |

**`vso.threads_full` is a narrow, low-privilege scope.** A review-focused app can read code and read/write all PR comments with just `vso.code` + `vso.threads_full`, avoiding the high-privilege `vso.code_write` entirely — a materially better consent screen. Add `vso.code_write` only if you also support voting, completing, labels or attachments.

**Likes are `POST`/`DELETE`, not `PUT`/`DELETE`.** Both return 200 with no body.

Thread status: `unknown | active | fixed | wontFix | closed | byDesign | pending`. Resolve with `PATCH {"status":"fixed"}`. Note the official samples send these enums as **integers** while responses return **strings**; both are accepted.

Comment types: `unknown | text | codeChange | system`. **`system` threads dominate the list** — in Microsoft's own sample, 6 of 8 threads are system-generated (merge attempts, reviewer changes, vote changes, ref updates). Filter them out for the conversation view, or key off `properties.CodeReviewThreadType` to render a rich activity feed instead.

**File- and line-anchored comments:**

```jsonc
"threadContext": {
  "filePath": "/new_feature.cpp",
  "rightFileStart": { "line": 5, "offset": 1 },   // new side (adds/context)
  "rightFileEnd":   { "line": 5, "offset": 13 },
  "leftFileStart": null,                          // old side (deletions)
  "leftFileEnd":   null
}
```
`line` is 1-based; `offset` is a character column. `threadContext: null` makes it a PR-level overview comment.

**Iteration anchoring — do not skip this:**

```jsonc
"pullRequestThreadContext": {
  "changeTrackingId": 1,
  "iterationContext": { "firstComparingIteration": 1, "secondComparingIteration": 2 }
}
```
The docs say `changeTrackingId` *"must be set for pull requests with iteration support."* Take it from `GET .../iterations/{n}/changes` → `changeEntries[].changeTrackingId`. **Omitting it is the number-one cause of comments that fail to track after a new push.**

Other details: `parentCommentId: 0` means top-level; `isDeleted` comments remain in the array with null content (skip them); `usersLiked[]` gives both the like count and whether the current user liked it; **cap of 500 comments per thread**. PR comments support Markdown (headers, tables, code fences, task lists, emoji, KaTeX, Mermaid, `@mentions`, `#123` work-item links, auto-linked bare URLs) but **not JavaScript or iframes**.

### 4.5 The diff problem

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List iterations | `GET .../pullRequests/{id}/iterations?includeCommits=` | `7.1` | `vso.code` |
| **Iteration changes** | `GET .../pullRequests/{id}/iterations/{iterationId}/changes?$top=&$skip=&$compareTo=` | `7.1` | `vso.code` |
| PR commits | `GET .../pullRequests/{id}/commits?$top=&continuationToken=` | `7.1` | `vso.code` |
| Arbitrary branch/commit diff | `GET .../diffs/commits?baseVersion=&targetVersion=&diffCommonCommit=true` | `7.1` | `vso.code` |

Iteration 1 is the source head at PR creation; each push adds an iteration. **`$compareTo=0` (the default) compares against the common commit between source and target — that is the full PR diff.** `$compareTo=N` gives "what changed since iteration N", i.e. the "changes since I last reviewed" view. `$top` defaults to 100 and **maxes at 2000**; page via the returned `nextSkip` / `nextTop` (both `0` when exhausted).

```jsonc
{ "changeEntries": [
    { "changeTrackingId": 1, "changeId": 1,
      "item": { "objectId": "<new blob sha>", "originalObjectId": "<old blob sha>", "path": "/new_feature.cpp" },
      "changeType": "edit",
      "originalPath": "/old/name.cpp" } ],
  "nextSkip": 0, "nextTop": 0 }
```

`changeType` is a **flags enum** — you will see combined values like `"edit, rename"`. Parse defensively. Filter out entries where `item.isFolder` or `gitObjectType == "tree"`.

**Confirmed: there is no unified-diff or patch endpoint anywhere in the Azure DevOps REST API.** Every diff-shaped endpoint (Diffs, Commit Changes, PR Iteration Changes) returns structured change entries — path, change type, blob SHAs — and never hunk text, `@@` headers or `+`/`-` lines. There is no equivalent of GitHub's `Accept: application/vnd.github.v3.diff`, and no `.diff` / `.patch` URL form at any api-version.

The Azure DevOps web UI uses an internal `POST {org}/{project}/_api/_versioncontrol/fileDiff` endpoint that returns diff blocks. It appears **nowhere on learn.microsoft.com**: unversioned, unscoped, unofficial, and subject to breaking change without notice. **Do not ship against it.**

`GET .../diffs/commits` is useful for arbitrary branch comparisons outside a PR, but note: it returns **file lists only, no text**; `diffCommonCommit` **defaults to `false`** (two-dot), which is *not* PR semantics — set it to `true`; and check **`allChangesIncluded`**, which is `false` when the list is truncated. For PRs, prefer iteration changes, because only they carry `changeTrackingId`.

### 4.6 Statuses, policies, labels, work items

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| PR statuses | `GET` / `POST .../pullRequests/{id}/statuses` | `7.1` | `vso.code` / `vso.code_status` |
| **Policy evaluations** | `GET /{org}/{project}/_apis/policy/evaluations?artifactId=` | **`7.1-preview.1`** | `vso.code` |
| Policy configurations (repo-scoped) | `GET /{org}/{project}/_apis/git/policy/configurations?repositoryId=&refName=` | `7.1` | `vso.code` |
| Labels | `GET` / `POST` / `DELETE .../pullRequests/{id}/labels[/{labelIdOrName}]` | `7.1` | `vso.code` / `vso.code_write` |
| Linked work items | `GET .../pullRequests/{id}/workitems` | `7.1` | `vso.code` |
| PR properties | `GET` / `PATCH .../pullRequests/{id}/properties` | `7.1` | `vso.code` / `vso.code_write` |
| PR attachments | `POST` / `GET` / `DELETE .../pullRequests/{id}/attachments/{fileName}` | `7.1` | `vso.code_write` / `vso.code` |

**The policy-evaluation artifactId is not the PR's own artifactId.** Verbatim from the docs: *"To generate an artifact ID for a pull request, use this template: `vstfs:///CodeReview/CodeReviewId/{projectId}/{pullRequestId}`"* — **no repositoryId**, and `{projectId}` must be the project **GUID**. Using `GitPullRequest.artifactId` (`vstfs:///Git/PullRequestId/{projectId}/{repositoryId}/{pullRequestId}`) here silently returns nothing. URL-encode the value.

`PolicyEvaluationStatus`: `queued | running | approved | rejected | notApplicable | broken`. `PolicyConfiguration.isBlocking` distinguishes required from optional checks — that is what drives your "required check" badge.

**For a "can this merge?" badge**, combine `pr.mergeStatus` (`conflicts`, `rejectedByPolicy`, `succeeded`, …) with policy evaluations on `isBlocking: true` configurations and the PR statuses list. Dedupe statuses on `context.genre` + `context.name`, keeping the latest by `updatedDate`, and group by `iterationId`.

`.../workitems` returns bare `{ id, url }` — budget an extra `_apis/wit/workitems?ids=…&fields=…` call (different scope, `vso.work`) to render titles.

### 4.7 How to render a PR diff on mobile

Azure DevOps gives you file-level change metadata and content-addressed blobs. **Your app is the diff engine.**

```
1. GET .../pullrequests/{id}                                  -> metadata, mergeStatus
2. GET .../pullRequests/{id}/iterations                       -> latest iteration N, commonRefCommit
3. GET .../pullRequests/{id}/iterations/{N}/changes?$top=2000  (omit $compareTo = full PR diff)
   -> page via nextSkip/nextTop; filter out trees/folders
4. POST .../itemsbatch  (includeContentMetadata: true)        -> isBinary / isImage for the whole file list, one call
5. Per file the user OPENS (lazy, never prefetch all):
     old: GET .../blobs/{item.originalObjectId}?$format=text   (skip when changeType = add)
     new: GET .../blobs/{item.objectId}?$format=text           (skip when changeType = delete)
6. Run Myers / histogram diff locally -> hunks
7. GET .../pullRequests/{id}/threads?$iteration={N}&$baseIteration={compareTo}
   -> overlay via threadContext.filePath + rightFileStart.line / leftFileStart.line
8. Post a comment with threadContext + pullRequestThreadContext.changeTrackingId
```

**Blobs are content-addressed, so cache them by SHA-1 forever.** This is the single biggest performance win available: reopening a PR after a push re-fetches only genuinely changed blobs. Bundle a JS or native Myers implementation (`diff-match-patch`, `jsdiff`, or a native histogram diff); normalize `\r\n` before splitting. On a phone, prefer unified rendering with word-level intra-line highlighting over side-by-side.

Suggested size gates (**our guidance — Microsoft publishes no byte limit**): render inline below ~512 KB; prompt between 512 KB and 2 MB; refuse above 2 MB or when `isBinary`. Render `isImage` files as before/after previews via `blobs/{sha}?$format=octetstream` rather than diffing.

### 4.8 Gaps and limitations

1. **No unified diff endpoint.** Client-side diffing is mandatory. The internal `_api/_versioncontrol/fileDiff` is unofficial — do not ship on it.
2. **No suggested-reviewers API.** The Pull Request Reviewers group has exactly eight operations and none is a suggestions endpoint. Build your own from `commits?searchCriteria.itemPath={changedFile}` authors plus required-reviewer identities from policy settings.
3. **No org-wide PR list.** `project` is `Required: True` on Get Pull Requests By Project, and there is no documented `GET {org}/_apis/git/pullrequests`. **A cross-org "PRs assigned to me" inbox requires fanning out per project** — the dominant rate-limit cost in the app. Cache the project list aggressively and stagger the fan-out.
4. **PR description truncated to 400 chars** in list responses.
5. **Linked work items return bare `{id,url}`** — extra call, different scope.
6. **Items API has no paging.**
7. **`isRequired` on reviewers is read-only.**
8. **Policy evaluations are still `7.1-preview.1`** and use a different artifactId shape.
9. **Iteration changes cap at `$top=2000`.**
10. **No documented byte-size limits** for item/blob downloads.
11. **`changeEntries` carries no binary signal** — you must join with `itemsbatch` metadata or sniff for NUL bytes.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/repositories/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/refs/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/items/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/blobs/get-blob?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests-by-project?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-reviewers/create-pull-request-reviewer?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-comment-likes/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iterations/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/diffs/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/policy/evaluations/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-labels/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/repos/git/limits?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/project/wiki/markdown-guidance?view=azure-devops>

---

## 5. Pipelines, Builds, Releases

**Versioning rule for this area:** under the 7.1 moniker, the Pipelines, Build, Release and Distributed Task surfaces are **GA at plain `7.1`** — the widely-copied `7.1-preview.1` on `_apis/pipelines` is obsolete. Under 7.2, *everything* is `7.2-preview.N`. The only endpoints still preview at 7.1 are **Checks** (`7.1-preview.1`) and **Test Results** (`7.1-preview.1`).

**Three hosts are in play:** `dev.azure.com` (pipelines, build, distributedtask, approvals/checks), `vsrm.dev.azure.com` (classic release only), `vstmr.dev.azure.com` (test results and code coverage only).

### 5.1 Pipelines and Builds

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List pipelines | `GET /{org}/{project}/_apis/pipelines?$top=&continuationToken=&orderBy=` | `7.1` | `vso.build` |
| Get pipeline | `GET .../pipelines/{pipelineId}` | `7.1` | `vso.build` |
| List runs | `GET .../pipelines/{pipelineId}/runs` | `7.1` | `vso.build` |
| Get run | `GET .../pipelines/{pipelineId}/runs/{runId}` | `7.1` | `vso.build` |
| **Queue a run** | `POST .../pipelines/{pipelineId}/runs` | `7.1` | `vso.build_execute` |
| Preview (expand YAML) | `POST .../pipelines/{pipelineId}/preview` | `7.1` | `vso.build` |
| **List builds (filterable)** | `GET /{org}/{project}/_apis/build/builds?definitions=&statusFilter=&resultFilter=&branchName=&$top=&continuationToken=` | `7.1` | `vso.build` |
| Get build | `GET .../build/builds/{buildId}` | `7.1` | `vso.build` |
| Queue build | `POST .../build/builds` | `7.1` | `vso.build_execute` |
| **Cancel build** | `PATCH .../build/builds/{buildId}` `{"status":"cancelling"}` | `7.1` | `vso.build_execute` |
| Definitions (with latest builds) | `GET .../build/definitions?includeLatestBuilds=true` | `7.1` | `vso.build` |
| Build changes / work items / artifacts | `GET .../build/builds/{buildId}/{changes\|workitems\|artifacts}` | `7.1` | `vso.build` |

**`runId` and `buildId` are the same integer.** You can hand a `runId` from the Pipelines API straight to `_apis/build/builds/{buildId}/timeline`. This is undocumented but universal, and it is the glue that makes a good mobile run view possible.

**Use the Build API for list screens, not the Pipelines API.** `GET _apis/pipelines/{id}/runs` has **no paging and no filters** (it dumps up to 10,000 runs) and its `state`/`result` enums are coarser — notably **there is no `partiallySucceeded`**, which is extremely common with `continueOnError` steps. `_apis/build/builds` has the full filter set and the full `BuildResult` enum (`none | succeeded | partiallySucceeded | failed | canceled`).

Queue body:

```jsonc
POST .../pipelines/{pipelineId}/runs?api-version=7.1
{
  "resources": { "repositories": { "self": { "refName": "refs/heads/main" } } },
  "templateParameters": { "buildConfiguration": "Release" },
  "stagesToSkip": ["Deploy_Prod"],
  "variables": { "myVar": { "value": "abc", "isSecret": false } }
}
```

Gotchas: **`"status": "cancelling"` has two Ls** and is spelled inconsistently with the rest of the API (`canceled`, `canceling`) — get it wrong and you get a silent no-op. On the legacy Build queue path, `Build.parameters` is a **JSON-encoded string**, not an object. `Build.queue` carries an explicit doc warning that it is deprecated. Paging on Builds–List uses the **`x-ms-continuationtoken` response header**, not a body field (*header name is the platform convention; not stated on that page — unverified*).

### 5.2 Timeline and logs — the heart of the run view

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| **Timeline (the whole run tree in one call)** | `GET .../build/builds/{buildId}/timeline[/{timelineId}]?changeId=` | `7.1` | `vso.build` |
| List logs | `GET .../build/builds/{buildId}/logs` | `7.1` | `vso.build` |
| **Get log text (rangeable)** | `GET .../build/builds/{buildId}/logs/{logId}?startLine=&endLine=` | `7.1` | `vso.build` |
| Logs with signed URLs | `GET .../pipelines/{pipelineId}/runs/{runId}/logs?$expand=signedContent` | `7.1` | `vso.build` |

`TimelineRecord` is exactly what a mobile run tree needs: `id`, **`parentId`** (builds the tree), `type` (`Stage`, `Phase`, `Job`, `Task`, `Checkpoint` — a **free-form string, not an enum**), `name`, **`order`** (sort siblings by this, not array order), **`identifier`** ("consistent across attempts" — use as your stable list key, *not* `id`), `state` (`pending | inProgress | completed`), `result` (`succeeded | succeededWithIssues | failed | canceled | skipped | abandoned`), `startTime`/`finishTime`, `percentComplete`, **`currentOperation`** (live status line), `log: { id }`, **`issues[]`** (`{ type: error|warning, message }`), `errorCount`/`warningCount`, `attempt`, **`previousAttempts[]`**, `workerName`.

Render `issues[]` inline under a failing task — it is the fastest path to "why did it fail" and costs no extra request. Use `errorCount`/`warningCount` as badges without opening logs at all.

**`$expand=signedContent` is the biggest mobile win in this area.** It returns `{ url, signatureExpires }` granting **limited-time anonymous access** to the log blob:

- **Send no `Authorization` header to that URL** — some blob/CDN endpoints reject the request if you do.
- Hand it straight to `URLSession` / OkHttp / a background downloader, bypassing your auth layer.
- Cache the log body, never the signed URL; re-fetch the list to re-sign.

**But note:** `startLine`/`endLine` exist only on the **Build** log endpoint, not the Pipelines one. For tailing a running job you need the Build endpoint. Send **`Accept: text/plain`** — the endpoint's declared media types include `application/zip`, which is the classic "why is my log binary garbage" bug. Compare `BuildLog.lineCount` between polls to detect new lines without refetching. (`startLine` being 1-based is *unverified*.)

### 5.3 Approvals and checks

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| **List YAML approvals** | `GET /{org}/{project}/_apis/pipelines/approvals?state=pending&$expand=steps&$expand=permissions&userIds=` | `7.1` | `vso.build` |
| **Approve / reject (YAML)** | `PATCH /{org}/{project}/_apis/pipelines/approvals` | `7.1` | `vso.build_execute` or `vso.pipelineresources_use` |
| List classic release approvals | `GET https://vsrm.dev.azure.com/{org}/{project}/_apis/release/approvals?statusFilter=pending&includeMyGroupApprovals=true` | `7.1` | `vso.release` |
| Approve (classic) | `PATCH https://vsrm.dev.azure.com/.../release/approvals/{approvalId}` | `7.1` | **`vso.release_manage`** |
| Environments | `GET /{org}/{project}/_apis/distributedtask/environments` | `7.1` | `vso.environment_manage` |
| **YAML deployment history** | `GET .../distributedtask/environments/{id}/environmentdeploymentrecords` | `7.1` | `vso.environment_manage` |
| Check configurations | `GET /{org}/{project}/_apis/pipelines/checks/configurations?$expand=settings` | **`7.1-preview.1`** | `vso.build` |

**These two approval APIs look alike and are not:**

| | YAML approvals | Classic release approvals |
|---|---|---|
| Host | `dev.azure.com` | `vsrm.dev.azure.com` |
| `approvalId` | **uuid** | **int32** |
| Method / shape | `PATCH` on the collection, **array** body | `PATCH` on `/{approvalId}`, **object** body |
| Comment field | **`comment`** (singular) | **`comments`** (plural) |
| Write scope | `vso.build_execute` / `vso.pipelineresources_use` | **`vso.release_manage`** (not `release_execute`) |
| `continuationToken` | string | int32 |

```jsonc
PATCH https://dev.azure.com/{org}/{project}/_apis/pipelines/approvals?api-version=7.1
[ { "approvalId": "aab27959-...", "status": "approved", "comment": "Approving" } ]
```

**Three traps for an approvals inbox:**
1. **`steps[]` and `permissions` are empty unless you pass `$expand=steps` and `$expand=permissions`.** Without them you render an empty card with no approver names and no way to tell whether the current user may act.
2. **At 7.1 the response carries no pipeline/run/stage reference** — you cannot tell the user *what* they are approving. The `Approval.pipeline` context object exists only at **`7.2-preview.2`**. This is the one genuine reason to use 7.2 in the app, and it applies to a single screen.
3. **`includeMyGroupApprovals` defaults to `false`** on the classic API — a mobile inbox will silently miss every group-assigned approval unless you set it to `true`.

Also honour `executionOrder: "inSequence"` — a step still in `uninitiated` status must not show an Approve button. Show `instructions` prominently; it is the message the pipeline author wrote for the approver.

**Scope warning:** `vso.environment_manage` is a **manage-only** scope (there is no read-only environment scope) and it inherits `vso.agentpools_manage`. That is a heavy consent ask for what is usually just deployment history. Consider deriving history from the build timeline instead.

### 5.4 Classic releases

| Capability | Method + Path (host `https://vsrm.dev.azure.com`) | api-version | Scope |
|---|---|---|---|
| List releases | `GET /{org}/{project}/_apis/release/releases?definitionId=&$top=&continuationToken=` | `7.1` | `vso.release` |
| Get release / definitions | `GET .../release/releases/{id}`, `.../release/definitions` | `7.1` | `vso.release` |
| Deployments | `GET .../release/deployments` | `7.1` | `vso.release` |
| **Deploy a stage** | `PATCH .../release/releases/{releaseId}/environments/{environmentId}` `{"status":"inProgress"}` | `7.1` | `vso.release_execute` |

**You send `status: "inProgress"` and the response comes back `"queued"`.** That is documented and correct — poll for the real transition rather than treating it as a failure. `continuationToken` is an **int32** across the whole release API, unlike the opaque string tokens elsewhere. Classic releases and YAML environments are **entirely disjoint**: a YAML deployment to Production will never appear in `_apis/release/deployments` — use `environmentdeploymentrecords`.

### 5.5 Stage retry

```jsonc
PATCH https://dev.azure.com/{org}/{project}/_apis/build/builds/{buildId}/stages/{stageRefName}?api-version=7.1
{ "state": "retry", "forceRetryAllJobs": false }
```

GA at 7.1, scope `vso.build_execute`, `StageUpdateType` is `cancel` or `retry` only, and it returns **200 with an empty body** — do not try to parse JSON. `stageRefName` is the **YAML stage identifier**, not the display name: take it from the timeline record's `identifier` field on the `type: "Stage"` record. `state: "cancel"` cancels one stage while leaving the rest of the run alone. A retry creates a new attempt and pushes the old records into `previousAttempts[]`.

### 5.6 Rendering a run on mobile

- **Pipeline list:** `GET _apis/build/definitions?includeLatestBuilds=true&$top=50&queryOrder=lastModifiedDescending` — one call returns definitions *plus* `latestBuild`/`latestCompletedBuild`, so the list shows live status with no N+1.
- **Run list:** `GET _apis/build/builds?definitions={id}&$top=25&queryOrder=queueTimeDescending`, paging on the continuation-token header.
- **Run detail:** one `GET .../builds/{id}` plus one `GET .../builds/{id}/timeline`. Build the tree from `parentId`, sort by `order`, key by `identifier`, badge with `errorCount`/`warningCount`, and show `issues[]` inline.
- **Task log:** on expand, `GET .../builds/{id}/logs/{record.log.id}?startLine={n}` with `Accept: text/plain`.

### 5.7 Gaps and limitations

1. **No live log streaming.** There is no documented WebSocket, SSE or long-poll endpoint anywhere in the pipelines/build/release/distributedtask surface. The web UI streams over an internal SignalR channel that is not public. (Concluded from exhaustive absence rather than an explicit negative statement — *strongly supported but not verbatim*.) Poll the timeline every 3–5 s while foregrounded, back off to 15–30 s after a couple of minutes, and stop entirely on background. `timeline?changeId=` looks like a delta mechanism but its semantics are **undocumented — unverified**.
2. **No console-tail endpoint.** Use `currentOperation` + `percentComplete` from the timeline for the collapsed row and fetch real log lines only on expand.
3. **No batch endpoint** — a run-detail screen costs about four round trips. Budget for that on cellular.
4. **Approvals have no change feed** — an approvals inbox must poll.
5. **No server-side search across runs**; `buildNumber` prefix matching (`buildNumber=abc*`) is the closest thing.
6. **Test results live on a third host** (`vstmr.dev.azure.com`), are **`7.1-preview.1`**, and need a fourth scope (`vso.test`). `resultsummarybybuild` returns `testFailures.newFailures`, which is the single best thing to surface on a phone. The `codecoverage` endpoint requires a `flags` query parameter whose legal values are **undocumented** (`flags=7` is community usage — *unverified*).
7. `IdentityRef.imageUrl`, `uniqueName`, `directoryAlias`, `inactive`, `isAadIdentity`, `isContainer` and `profileUrl` are all **deprecated** — bind only to `id`, `displayName`, `descriptor` and `_links`.
8. **Scope cost:** a fully featured pipelines experience wants `vso.build`, `vso.build_execute`, `vso.release`, `vso.release_execute`, `vso.release_manage`, `vso.environment_manage` and `vso.test`. That is a heavy consent screen — **ship read-only first with `vso.build` + `vso.release`.**
9. `keepForever` for build retention is **not in the documented 7.1 request schema** (retention leases are a separate API) — *unverified*, do not ship without testing.
10. `DELETE _apis/build/builds/{buildId}` scope is *unverified* (page not fetched; `vso.build_execute` assumed).

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/pipelines/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/runs/run-pipeline?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/logs/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds/update-build?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds/get-build-log?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/timeline/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/stages/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/approvals/query?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/approvals/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/check-configurations/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environmentdeployment-records/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/release/approvals/update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/release/releases/update-release-environment?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/testresults/resultsummarybybuild/query?view=azure-devops-rest-7.1>

---

## 6. Notifications and Activity

### 6.1 The headline answer: there is no notification inbox API

**Azure DevOps has no equivalent of GitHub's `GET /notifications`.** No REST API returns a user's delivered notification items, and there is no read/unread state anywhere in the product's API surface to query or mutate.

This is architectural, not an oversight. From *About Notifications*:

> "When an event occurs in Azure DevOps, the event content is compared with every subscription of that event type. A notification is generated for every subscription/event match that meets the filter conditions. **Notifications are delivered through email or service hook**, based on the delivery properties defined in the subscription."

And from the Notification REST index:

> "**The primary delivery channel for notifications today is email.** … The Notification APIs primarily provide the ability to create and manage subscriptions."

Corroborating evidence that this is exhaustive rather than undocumented:

- The Subscriptions operation group has exactly eight operations — all subscription CRUD, none returning notifications.
- `ISubscriptionChannel.type` values are `EmailHtml` and `User`. **There is no in-app, device or push channel type.**
- The only endpoint literally named "notifications" is Service Hooks' `_apis/hooks/subscriptions/{id}/notifications` — that is the **delivery log for one webhook subscription you own**, not a user inbox.
- `_apis/notification/diagnosticlogs` returns **job-level** delivery telemetry (counts, timings, email counters) — aggregate, not per-user items.
- `_apis/notification/statistics` is **not documented** at 7.1 or 7.2.

**Consequence: a GitHub-style inbox must be synthesized, either client-side or in your own backend. There is nothing to read.**

### 6.2 Notification API (subscriptions)

All GA at `7.1` on `https://dev.azure.com/{org}`.

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List / get subscriptions | `GET /_apis/notification/subscriptions[/{id}]?targetId=&queryFlags=` | `7.1` | `vso.notification` |
| Create / update / delete | `POST` / `PATCH` / `DELETE /_apis/notification/subscriptions[/{id}]` | `7.1` | `vso.notification_write` |
| Query subscriptions | `POST /_apis/notification/subscriptionquery` | `7.1` | `vso.notification` |
| Subscription templates | `GET /_apis/notification/subscriptiontemplates` | `7.1` | `vso.notification` |
| Per-user settings | `PUT /_apis/notification/Subscriptions/{id}/usersettings/{userId}` | `7.1` | `vso.notification_write` |
| Event types | `GET /_apis/notification/eventtypes?publisherId=` | `7.1` | `vso.notification` |
| Settings / subscribers / diagnostics | `GET /_apis/notification/{settings\|subscribers/{id}\|subscriptions/{id}/diagnostics}` | `7.1` | `vso.notification` |
| Diagnostic logs | `GET /_apis/notification/diagnosticlogs/{source}/entries/{entryId}` | `7.1` | `vso.notification_diagnostics` |

**The Artifact filter is the documented "follow this thing" mechanism** — and it is the closest thing to the missing Follow API from §2.10:

```jsonc
POST /_apis/notification/subscriptions?api-version=7.1
{ "filter": { "type": "Artifact", "artifactType": "WorkItem", "artifactId": "1064327" } }
{ "filter": { "type": "Artifact", "artifactType": "PullRequestId",
              "artifactId": "{projectId}/{repositoryId}/{prId}" } }
```

There is also a role-based **Actor** filter:
`{"type":"Actor","inclusions":["author","reviewer","changedReviewers"],"exclusions":["initiator"],"eventType":"ms.vss-code.git-pullrequest-event"}`.

Creating a subscription with no `subscriber` defaults to the calling user, so a user *can* manage their own personal subscriptions without admin rights. **However, this still only produces email — it does not create anything your app can read back as an inbox.**

Gotchas: `Update` is `PATCH` but `Update Subscription User Settings` is `PUT` with different path casing (`/Subscriptions/`). Multiple conditions in `subscriptionquery` are **OR'd**, not AND'd. `SubscriptionStatus` has 16 values — watch for `jailedByNotificationsVolume` and `disabledAsDuplicateOfDefault`, which silently kill subscriptions you created. Check `customSubscriptionsAllowed` on an event type before offering it in UI.

### 6.3 Service Hooks

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List / get / create / replace / delete | `GET`/`POST`/`PUT`/`DELETE /_apis/hooks/subscriptions[/{id}]` | `7.1` | `vso.work`, `vso.build`, `vso.code` |
| Query subscriptions | `POST /_apis/hooks/subscriptionsquery` | `7.1` | same |
| Delivery log | `GET /_apis/hooks/subscriptions/{id}/notifications?maxResults=&status=&result=` | `7.1` | same |
| Consumers / publishers | `GET /_apis/hooks/{consumers\|publishers}[/{id}]` | `7.1` | same |
| Test notification | `POST /_apis/hooks/testnotifications` | `7.1` | same |

Create body: `{ publisherId, eventType, resourceVersion, consumerId: "webHooks", consumerActionId: "httpRequest", publisherInputs: { projectId, ... }, consumerInputs: { url } }`.

**Scope note:** `vso.hooks`, `vso.hooks_write` and `vso.hooks_interact` are each annotated **"(No longer public.)"** in the scope table. You obtain hook rights *transitively* — `vso.code`, `vso.work` and `vso.build` each inherit `vso.hooks_write`, and the hooks REST pages list exactly those three scopes.

**Event types worth wiring** (publisher `tfs` unless noted): `git.push`, `git.pullrequest.created`, `git.pullrequest.updated` (with `notificationType` = `PushNotification` / `ReviewersUpdateNotification` / `StatusUpdateNotification` / `ReviewerVoteNotification`), `git.pullrequest.merged`, `ms.vss-code.git-pullrequest-comment-event`, `workitem.created` / `.updated` / `.deleted` / `.restored`, `ms.vss-work.work-item-comment-event`, `build.complete`, `ms.vss-pipelines.run-state-changed-event`, `ms.vss-pipelines.stage-state-changed-event`, `ms.vss-pipelinechecks-events.approval-pending`.

**`pullrequestReviewersContains` is the single most valuable filter for this app** — it lets one subscription target "PRs where user X is a reviewer" *server-side*, instead of filtering a firehose. Work-item events filter on `areaPath`, `workItemType` and `changedFields`.

**The onboarding wall.** Verbatim: *"You need the Edit subscriptions and View subscriptions permissions. **By default, only project administrators have these permissions.**"* The webhook page is stricter still, requiring Project Collection Administrators or Project Administrators membership. And subscriptions are **project-scoped** (`publisherInputs.projectId` is always present). **A user with 20 projects across 3 organizations cannot self-serve push notifications.** There is a partial mitigation — *"If the user sets up a subscription for a resource that they don't otherwise have permission to access, the subscription doesn't get triggered"* — but the admin requirement stands.

Delivery semantics are only partly documented: retries exist (`NotificationDetails.requestAttempts`, `Subscription.probationRetries`, `SubscriptionStatus.onProbation`, `disabledBySystem`) but **the retry count, backoff schedule, request timeout and the failure threshold that triggers probation are all undocumented — unverified**. Webhook endpoints must be HTTPS and cannot target localhost or special-range addresses. Set **Resource details to send = Minimal** and call back into Azure DevOps with the *user's* token, so permission trimming is preserved.

### 6.4 Pull-based activity: what actually exists

| Purpose | Endpoint | api-version | Scope |
|---|---|---|---|
| Recently touched work items | `GET /{org}/_apis/work/accountmyworkrecentactivity` | `7.1` | `vso.work` |
| Assigned to me | `POST /{project}/{team}/_apis/wit/wiql` with `@Me` | `7.1` | `vso.work` |
| PRs I review or created | `GET /{project}/_apis/git/pullrequests?searchCriteria.reviewerId=&...creatorId=` | `7.1` | `vso.code` |
| **Work item delta feed (watermark)** | `GET /{project}/_apis/wit/reporting/workitemrevisions?continuationToken=&includeDiscussionChangesOnly=` | `7.1` | `vso.work` |
| PR comment threads | `GET .../pullRequests/{id}/threads` | `7.1` | `vso.code` / `vso.threads_full` |
| Favorites | `GET /{org}/_apis/favorite/favorites?artifactType=&artifactScopeType=` | `7.1-preview.1` | **`vso.profile`** |

**`accountmyworkrecentactivity` is outbound activity, not an inbox.** `WorkItemRecentActivityType` is only `visited | edited | deleted | restored` — it tells you what *you* touched, not what happened *to you*. It is org-scoped and unpaged.

**`reporting/workitemrevisions` is the only true watermark feed in the product.** The `continuationToken` *"acts as a waterMark"*; the response carries `{ values, nextLink, continuationToken, isLastBatch }`. `includeDiscussionChangesOnly=true` narrows it to history and comment changes — the closest thing to a comment firehose. `startDateTime` and the token are mutually exclusive. **There is no equivalent reporting feed for pull requests**; PRs must be polled with `searchCriteria` and diffed client-side on `lastMergeSourceCommit` and thread `lastUpdatedDate`.

**Mentions are per-work-item only.** `CommentMention` gives `{ artifactId, artifactType, commentId, targetId }`, but there is **no org-wide "mentions of me" query**. Building that feed means enumerating candidate work items first — expensive. `accountmyworkrecentmentions` is **not documented** at 7.1 or 7.2.

### 6.5 There is no Microsoft push service for third parties

**Confirmed: no APNs/FCM relay, no device-registration endpoint, no push channel in any Azure DevOps API.** Subscription channel types are email and service hook only. Searches for an Azure DevOps push service surface only **Azure Notification Hubs**, a separate Azure product you would operate and pay for yourself. The service-hooks overview does mention "send a push notification to your team's mobile devices when a build fails", but that describes third-party consumers (messaging apps, App Center), not an Azure DevOps push API.

**The three viable architectures:**

1. **Service hook → your backend → APNs/FCM.** Lowest latency and the richest server-side filtering (`pullrequestReviewersContains`, `areaPath`, `changedFields`). Cost: a project admin must create subscriptions **per project**. Shape: one webhook receiver, one subscription per (project × event type), map `resource` to subscriber device tokens, de-dupe, and call back with the user's token for details.
2. **Polling with the user's own token.** No admin needed, works on day one. `reporting/workitemrevisions` with `continuationToken` for work items, `git/pullrequests?searchCriteria.reviewerId={me}` plus per-PR thread diffing for PRs. Cannot produce true background push on iOS without a server, and it consumes rate budget.
3. **Hybrid — recommended.** Ship polling as the zero-onboarding default; offer service hooks as an opt-in "instant notifications" upgrade that an admin enables per project. This is the only design that both works for a first-run individual user and scales to an engaged team.

### 6.6 Gaps

1. **No notification inbox API. No read/unread state.** Hard gap.
2. **No push relay.** You must run a backend.
3. **Service hooks require a project admin, per project** — the dominant onboarding constraint for a multi-project, multi-org user.
4. **No PR reporting/delta feed** (work items have one; PRs do not).
5. **No org-wide mentions query.**
6. Service-hook retry/backoff/timeout semantics undocumented (*unverified*).
7. `workitem.commented` (in the REST subscriptions sample) versus `ms.vss-work.work-item-comment-event` (in the events reference) — both appear in first-party docs; **which is canonical at 7.1 is unverified**.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/notification/?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/notification/subscriptions/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/notification/event-types/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/organizations/notifications/about-notifications?view=azure-devops>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/hooks/subscriptions/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/hooks/notifications/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/service-hooks/events?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/service-hooks/services/webhooks?view=azure-devops>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/reporting-work-item-revisions/read-reporting-revisions-get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/favorite/favorites/get-favorites?view=azure-devops-rest-7.1>

---

## 7. Search

Host is **`https://almsearch.dev.azure.com`** (`alm` + `search`, one word, no hyphen). Rather than hard-coding it, resolve it properly: `GET https://dev.azure.com/{org}/_apis/resourceAreas/ea48a0a1-269c-42d8-b8ad-ddc8fcdcf578?api-version=5.0-preview.1` (unauthenticated) and use the returned `locationUrl`.

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| **Code search** | `POST /{org}/{project}/_apis/search/codesearchresults` | `7.1` (GA) | `vso.code` |
| **Work item search** | `POST /{org}/{project}/_apis/search/workitemsearchresults` | `7.1` (GA) | `vso.work` |
| **Wiki search** | `POST /{org}/{project}/_apis/search/wikisearchresults` | `7.1` (GA) | `vso.wiki` |
| Package search | `POST /{org}/_apis/search/packagesearchresults` (**no `{project}`**) | `7.1` | `vso.packaging` |
| Repo / TFVC index status | `GET /{org}/{project}/_apis/search/status/{repositories/{repo}\|tfvc}` | `7.1` | `vso.code` |

**Use 7.1** — the 7.2 contracts are byte-identical except for the preview label. **Board search and commit search have no REST API**; commit search is UI-only.

Request body: `searchText`, `$top`, `$skip`, `filters` (an untyped `string -> string[]` dictionary), `$orderBy` (`[{field, sortOrder}]`, or `null` for relevance), `includeFacets`. Code search adds `includeSnippet`.

Filter keys from the official samples:
- **Code:** `Project`, `Repository`, `Path`, `Branch`, `CodeElement` (values `def`, `class`, `comment`).
- **Work item:** `System.TeamProject`, `System.AreaPath`, `System.WorkItemType`, `System.State`, `System.AssignedTo` (format `"John Doe <jodoe@microsoft.com>"`).
- **Wiki:** only `Project` is shown; a `Wiki` filter key is **undocumented — unverified**.

**Case trap:** filter keys are PascalCase or `System.`-prefixed, but `$orderBy.field` and work-item response `fields` keys are **lowercase** (`filename`, `system.id`).

**`infoCode` is a soft status returned inside an HTTP 200 — you must read it.** `0` Ok · `1` account being reindexed · `2` indexing not started · `3` invalid request · `4` prefix wildcard not supported · `5` multi-word with code facet not supported · `6` account being onboarded · `7` onboarding or reindexing · **`8` top value trimmed to max result allowed** · `9` branches being indexed · `10` faceting not enabled · `11` work items not accessible · `19` phrase queries with code type filters not supported · `20` wildcard queries with code type filters not supported. **Codes 1/2/6/7/9 mean "results incomplete, indexing in progress" — show a banner, not "no results".**

**Result highlighting gotcha:** `CodeResult.matches` is keyed by field (`content`, `fileName`) with `[{charOffset, length}]`. **Microsoft's own sample contains `{"charOffset": 0, "length": -1}`** — guard your slicing against `-1`. Work-item hits use `<highlighthit>…</highlighthit>` markup inline in the field values.

**Code Search requires the marketplace extension.** Verbatim: *"[Code Search]: Provides fast, flexible, and precise search results across all your code repositories. **Required for searching code content.**"* Extension id `ms.vss-code-search`. It is also *"Not available for Stakeholder users"* — at least **Basic** access is needed. **Work Item Search needs no extension** (*"available by default when the Boards service is installed and enabled"*), and neither do wiki or package search.

**The error returned when the extension is absent is undocumented — do not code against a guessed status.** Detect it explicitly: `GET https://extmgmt.dev.azure.com/{org}/_apis/extensionmanagement/installedextensionsbyname/ms/vss-code-search?api-version=7.1-preview.1`. Note that requires `vso.extension_manage`, a heavy scope — make the check lazy and cache the result. Treat `installState.flags` containing `disabled` as distinct from "absent".

**Limits are largely undocumented.** Max `$top`, max `$skip` and the total-result ceiling are **not stated anywhere in 7.1 or 7.2**. The only proof a cap exists is `infoCode 8`. The largest value in any official sample is `$top: 50`. **Do not hard-code 1000 or 200** — discover empirically and treat `infoCode == 8` as the clamp signal. Documented adjacent facts: the UI highlights only the first 100 matches; *"Code search doesn't work for forked repositories"*; only the default branch is indexed by default.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/search/code-search-results/fetch-code-search-results?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/search/work-item-search-results/fetch-work-item-search-results?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/search/wiki-search-results/fetch-wiki-search-results?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/project/search/get-started-search?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/extend/develop/work-with-urls?view=azure-devops>

---

## 8. Wiki

All 14 operations are **GA at `7.1`**. At 7.2 they are all preview, and the revisions differ (`Wikis–Create` is `7.2-preview.2`, the rest `7.2-preview.1`) — **pin 7.1**. Base: `https://dev.azure.com/{org}/{project}/_apis/wiki/`.

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| List / get wikis | `GET wikis[/{wikiId}]` | `7.1` | `vso.wiki` |
| Create / update / delete wiki | `POST` / `PATCH` / `DELETE wikis[/{wikiId}]` | `7.1` | `vso.wiki_write` |
| **Get page by path** | `GET wikis/{wikiId}/pages?path=&recursionLevel=&includeContent=true&versionDescriptor.*` | `7.1` | `vso.wiki` |
| Get page by id | `GET wikis/{wikiId}/pages/{id}?includeContent=true` | `7.1` | `vso.wiki` |
| Create or update page | `PUT wikis/{wikiId}/pages?path=&comment=` + `If-Match` | `7.1` | `vso.wiki_write` |
| Delete page | `DELETE wikis/{wikiId}/pages?path=` | `7.1` | `vso.wiki_write` |
| Page moves | `POST wikis/{wikiId}/pagemoves` | `7.1` | `vso.wiki_write` |
| **Pages batch (+ view stats)** | `POST wikis/{wikiId}/pagesbatch` | `7.1` | `vso.wiki` (read scope on a POST) |
| Page stats | `GET wikis/{wikiId}/pages/{pageId}/stats?pageViewsForDays=` | `7.1` | `vso.wiki` |
| Attachments | `PUT wikis/{wikiId}/attachments?name={name}` | `7.1` | `vso.wiki_write` |

**Content negotiation is how you get raw Markdown.** The docs say: *"Content negotiation is done based on the `Accept` header sent in the request."* The 200 row declares media types `application/json`, `text/plain` and `application/zip`.

| You want | Send | You get |
|---|---|---|
| Metadata + content as JSON | `Accept: application/json` + `includeContent=true` | `WikiPage` JSON with `content` populated, plus an `ETag` |
| Metadata only | `Accept: application/json` | `"content": ""` — an **empty string**, not an omitted field |
| **Raw Markdown** | `Accept: text/plain` | raw body, chunked, `ETag` still present |
| Zip | `Accept: application/zip` | binary |

**There is no `.../pages/{id}/text` sub-path** — it does not exist. The only sub-path under `/pages/{id}` in the entire Wiki API is `/stats`. (`getPageByIdText` is a TypeScript client method name, not a URL.) Page content is Markdown.

**ETag handling is inconsistently documented.** The request-header table names the header `Version` but says *"To be populated in the If-Match header of the request."* In practice: **create sends no `If-Match`** (returns 201); **update sends `If-Match: <etag>`** (returns 200 with a new ETag). **The mismatch status code — 409 versus 412 — is undocumented on every Wiki operation; handle both.** 7.2 adds a documented `404` for "wiki repository is disabled, deleted, or user does not have access."

**Pages Batch** is the bulk-enumeration and view-stats API. Body `{ top, continuationToken, pageViewsForDays }`; returns `WikiPageDetail[]` with **only `id`, `path` and `viewStats`** — no content, no ordering, no `subPages`. The continuation token arrives in a **response header** (rendered inconsistently as `x-MS-ContinuationToken` / `x-ms-continuationtoken` — read case-insensitively) and is sent back in the **body**. `viewStats` is `[{day, count}]` and appears only when `pageViewsForDays` is passed; zero-view days are omitted. **View-stats retention is 30 days**, and a "visit" is de-duplicated per user per 15-minute interval — do not build a 90-day trend UI.

**Attachments:** `name` is a **required query parameter**, not a path segment; the body is raw binary with `Content-Type: application/octet-stream`. Response 201 returns `{name, path}` such as `/.attachments/Attachment845.png`. **Doc bug: the official sample omits the required `name` parameter — do not copy it.** Whether base64 is accepted is *unverified*.

**Code wiki versus project wiki.** `WikiType` is `projectWiki` or `codeWiki`. A code wiki additionally needs `repositoryId`, `mappedPath` and `version` on create. To tell them apart in a response: for a project wiki, `id` and `repositoryId` are the **same GUID**, `mappedPath` is `"/"`, and `versions[0].version` is `"wikiMaster"`; for a code wiki those differ. `Wikis–Update` accepts only `name` and `versions[]` — type, repositoryId and mappedPath are immutable.

**Two more traps.** First, **every by-id operation lacks `versionDescriptor.*`** — Get Page By Id, Delete Page By Id and Pages–Update are locked to the wiki's default version, so for a code wiki with multiple mapped branches you must use the path-based forms. Second, **`path` and `gitItemPath` are different strings**: `path` is URL-encoded including the leading slash (`%2FSamplePage973`, spaces as `%20`), while `gitItemPath` is hyphenated with a `.md` extension (`/nhhm-mjmj.md`). Never derive one from the other. Wiki file size cap: **25 MB**.

**Gap:** a wiki **page comments** surface exists in the TypeScript `WikiRestClient` (`addComment`, `listComments`, reactions) but is **absent from the REST reference** — treat it as unsupported.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/pages/get-page?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/pages/create-or-update?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/pages-batch/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/page-stats/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/attachments/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/wikis/create?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/azure/devops/release-notes/2019/wiki/sprint-160-update>

---

## 9. Identity, Graph and Avatars

| Capability | Method + Path | api-version | Scope |
|---|---|---|---|
| **Get avatar** | `GET https://vssps.dev.azure.com/{org}/_apis/graph/Subjects/{subjectDescriptor}/avatars?size=medium` | `7.1` (GA) | `vso.graph` |
| List users / groups | `GET https://vssps.dev.azure.com/{org}/_apis/graph/{users\|groups}?continuationToken=&scopeDescriptor=` | **`7.1-preview.1`** | `vso.graph` |
| **People picker (search)** | `POST https://vssps.dev.azure.com/{org}/_apis/graph/subjectquery` | **`7.1-preview.1`** | `vso.graph` |
| Batch resolve descriptors | `POST https://vssps.dev.azure.com/{org}/_apis/graph/subjectlookup` | `7.1-preview.1` | `vso.graph` |
| Memberships | `GET .../graph/Memberships/{subjectDescriptor}?direction=up\|down` | `7.1-preview.1` | `vso.graph` |
| GUID to descriptor | `GET .../graph/descriptors/{storageKey}` | `7.1` (GA) | `vso.graph` |
| Descriptor to GUID | `GET .../graph/storagekeys/{subjectDescriptor}` | `7.1` (GA) | `vso.graph` |
| **Identity search (with email)** | `GET https://vssps.dev.azure.com/{org}/_apis/identities?searchFilter=General&filterValue=` | `7.1` (GA) | **`vso.identity`** |
| Team members | `GET https://dev.azure.com/{org}/_apis/projects/{projectId}/teams/{teamId}/members` | `7.1` | `vso.profile`, `vso.project` |
| **Assignable users for a field** | `GET /{org}/{project}/_apis/wit/workitemtypes/{type}/fields/{field}?$expand=All` | `7.1` | `vso.work` |

### 9.1 Avatars: the mobile-critical detail

**The Graph avatar response is JSON, not image bytes.** The complete `Avatar` definition is four fields: `isAutoGenerated`, `size` (`small | medium | large`), `timeStamp`, and **`value`, typed `string[] (byte)`** — i.e. a C# `byte[]`, which serializes to a base64 string. (That base64 encoding is *inferred from the type*, not verbatim-documented; there is **no sample request or response on the page at all**.) There is **no `isUrl` field**, and the `format` query parameter is typed as a bare `string` with **no enum and no description** — its legal values are **undocumented**.

Identity references instead expose `_links.avatar.href` pointing at **`https://dev.azure.com/{org}/_apis/GraphProfile/MemberAvatars/{descriptor}`**. That route has **no reference page, no operation group, no api-version and no scope table anywhere on learn.microsoft.com** — yet it appears verbatim in official sample responses across Graph, Subject Lookup and WIT Comments, and `IdentityRef.imageUrl` is deprecated with the note *"Available in the 'avatar' entry of the IdentityRef '_links' dictionary"*. So it is real, official-by-sample, and undocumented-by-contract. Note the host inversion: Graph avatars live on `vssps.dev.azure.com`, but `_links.avatar.href` points at `dev.azure.com`. Groups get no `avatar` link at all — render a fallback.

**Do avatar URLs require an `Authorization` header?** **The docs never say, either way.** There is no sentence granting anonymous access to any avatar URL, no "publicly accessible" note, and no CDN/cache note. What *is* established: the Graph Avatars operation carries a Security/Scopes table requiring `vso.graph` (so it is an authorized surface), and the REST getting-started page frames every request as credential-bearing.

**Engineering recommendation (our judgment, not from the docs): do not put an avatar URL directly into a mobile `Image` view.** Fetch avatars through your authenticated HTTP client, cache the bytes locally **keyed by the storage-key GUID**, and treat an HTML body or a 302-to-signin as "no avatar" rather than image data. For list views, `POST _apis/graph/subjectlookup` returns `_links.avatar.href` for many subjects in one call.

### 9.2 People pickers

**`POST _apis/IdentityPicker/Identities` is internal and undocumented — do not build against it.** The only learn.microsoft.com hits for "IdentityPicker" are the security-namespace reference and old server release notes. No method, path, api-version, schema or scope is published.

**Use Graph Subject Query instead** — it is the documented people picker:

```jsonc
POST https://vssps.dev.azure.com/{org}/_apis/graph/subjectquery?api-version=7.1-preview.1
{ "query": "jamal", "subjectKind": ["User","Group"], "scopeDescriptor": "scp.<base64>" }
```

*"Results will be returned in a batch with no more than 100 graph subjects"* — a hard cap of 100 with **no paging parameter**. `subjectKind` is documented capitalized in the request but returned lowercase. **`GraphSubject` has no `mailAddress` or `principalName`** — if your picker rows need email, use the Identities API instead: `GET .../_apis/identities?searchFilter=General&filterValue=jamal` (scope `vso.identity`, GA), where `General` means *"display name, account name, or unique name"*. One call returns GUID, legacy descriptor, subjectDescriptor and `properties.Mail`.

### 9.3 Assignable users

**There is no per-project "assignable identities" endpoint.** The best available options, in order:

1. **WIT field allowed values — this *is* the Assigned To picker list**, scoped to project and work item type: `GET /{project}/_apis/wit/workitemtypes/{type}/fields/System.AssignedTo?$expand=All`. The allowed values carry everything a picker row needs — `displayName`, `id`, `uniqueName`, `descriptor`.
2. **Team members** — `GET /_apis/projects/{projectId}/teams/{teamId}/members`. **Trap:** the official sample's `identity` is the thin legacy shape (`id`, `displayName`, `uniqueName`, `url`, `imageUrl`) with **no `descriptor` and no `_links`**, despite the schema declaring both. Plan a fallback to resolve descriptors.
3. **Graph Subject Query** for org-wide type-ahead.

### 9.4 The four identifiers

**`identityRef.id` (a GUID) is the storage key / VSID. It is not a descriptor.** Verbatim: *"id | string (uuid) | Identity Identifier. **Also called Storage Key, or VSID**"*. And from the Graph overview:

> "VSIDs uniquely identify a user or group within an account. They do not uniquely identify users or groups in cross-account scenarios. **Descriptors uniquely identify users and groups across all accounts.**"
> "**We do not recommend persisting descriptors** because there are several scenarios where they can change over time."

Conversions: `GET .../graph/descriptors/{storageKey}` (GUID → descriptor) and `GET .../graph/storagekeys/{subjectDescriptor}` (descriptor → GUID), both GA at 7.1 and returning `{value, _links}`. A cheaper one-hop alternative is `GET _apis/identities?identityIds={guid}`, which returns the GUID, the legacy descriptor and the subject descriptor together.

Full chain from an identity reference to an avatar: `identityRef.id` → `graph/descriptors/{guid}` → subject descriptor → `graph/Subjects/{descriptor}/avatars?size=medium`. **Cache on the GUID, never the descriptor** — Microsoft explicitly says descriptors rotate.

Watch for a **fourth** identifier: the legacy `IdentityDescriptor` (`Microsoft.IdentityModel.Claims.ClaimsIdentity;{tenant}\user@dom`), exposed as `Identity.descriptor` and `GraphSubject.legacyDescriptor` (*"[Internal Use Only]"*), required by the Security APIs.

### 9.5 Gaps

1. **Avatar auth behaviour is undocumented.** Assume authenticated; fetch and cache yourself.
2. **`_apis/GraphProfile/MemberAvatars/{descriptor}` and `_api/_common/identityImage?id={guid}` are undocumented** despite appearing in official samples.
3. **`_apis/IdentityPicker/Identities` is internal.**
4. **`subjectquery` caps at 100 results with no paging.**
5. **Most of `IdentityRef` is deprecated** — `imageUrl`, `uniqueName`, `directoryAlias`, `inactive`, `isAadIdentity`, `isContainer`, `profileUrl`. Bind only to `id`, `displayName`, `descriptor` and `_links`.
6. Graph `format` query-parameter legal values undocumented.
7. Team-member responses may omit `descriptor` and `_links` despite the schema.

**Citations**

- <https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/avatars/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/users/list?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/subject-query/query?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/descriptors/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/storage-keys/get?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/ims/identities/read-identities?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/core/teams/get-team-members-with-extended-properties?view=azure-devops-rest-7.1>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-types-field/get?view=azure-devops-rest-7.1>

---

## 10. Cross-cutting Concerns

### 10.1 Authentication — read this before scoping anything else

**Azure DevOps OAuth (`app.vssps.visualstudio.com/oauth2`) is dead for new apps.**

| Milestone | Status |
|---|---|
| New app registrations blocked | **April 23, 2025** — *"the Azure DevOps OAuth app platform is no longer accepting new app registrations"* |
| Full retirement | *"scheduled for full deprecation in 2026"*; existing apps *"stop working when the service is fully deprecated in 2026"* |
| Exact retirement date | **Not published as of 2026-09-10 — unverified** |
| Global PATs decommissioned | **December 1, 2026** |

The Learn page carries a hard banner: *"Use Microsoft Entra ID OAuth for new applications. Azure DevOps OAuth 2.0 is deprecated and no longer accepts new registrations."*

**The replacement is Microsoft Entra ID OAuth:**

- Azure DevOps resource identifier: **`499b84ac-1321-427f-aa17-267ca6975798`**
- Azure DevOps resource URI: `https://app.vssps.visualstudio.com`
- Register a standard Microsoft identity platform app; under **API permissions**, *"Instead of Microsoft Graph, select `Azure DevOps` from the list of resources"* and add **delegated** permissions.
- *"Use the `.default` scope when requesting a token with all scopes that the app is permissioned for."*
- *"All Azure DevOps REST APIs accept Entra tokens wherever Azure DevOps OAuth access tokens are accepted."*

**Granular `vso.*` scopes DO work with Entra — but delegated flows only.** Since September 2023, Entra apps have scope parity with the old platform. Before that, `user_impersonation` was the only option. The limitation, verbatim: *"These new permissions are only available for delegated flows, they do not exist as application permissions on app-only flows."* Service principals and managed identities get coarse access only. For a user-facing mobile app this is fine — you want delegated anyway.

**⚠️ The showstopper to resolve before committing to a consumer launch:**

> "**Microsoft Entra apps don't natively support Microsoft account (MSA) users for the Azure DevOps resource.** If you're building an app that must cater to MSA users or support both Microsoft Entra and MSA users, **Azure DevOps OAuth apps remain your best option.** Microsoft is currently working on native support for MSA users through Microsoft Entra OAuth."

That page was last updated **2026-05-08** and still says this. It is a direct contradiction inside Microsoft's own documentation: **the only recommended path for personal-Microsoft-account users is a platform that no longer accepts new registrations.** Personal MSA accounts are common among individuals and small organizations. **Plan for Entra-tenant users only at v1, and track this gap as a launch-blocking dependency for the consumer segment.**

**A stale FAQ you will trip over.** The deprecated Azure DevOps OAuth page still says: *"Q. Can I use OAuth with mobile applications? **A. No.** … **Alternative for mobile apps**: Use personal access tokens."* That answer is scoped to the **legacy platform**, which had no PKCE public-client support. It is contradicted by the same site's Entra guidance and by MSAL. **Do not build a PAT-based consumer mobile app on the strength of it.** The `authentication-guidance` page describes PATs as *"Highest risk of the common choices"*, best only for *"short-lived personal scripts, one-off testing, or legacy scenarios"*, and says to *"Use personal access tokens sparingly."* Asking every user to hand-mint and paste a long-lived bearer secret is a UX and security non-starter.

**The correct mobile flow:** Microsoft Entra ID, **public client, authorization code + PKCE, via MSAL**, with refresh tokens in the MSAL cache. Headless variants should use the device authorization grant.

**Treat tokens as opaque.** From summer 2025 Azure DevOps further encrypts authentication tokens: *"clients can't read token payloads. Any application that decodes tokens to extract claims breaks."* Get user and org identity from `_apis/profile/profiles/me`, `_apis/connectionData` or Graph — never from JWT claims.

**Other constraints:** OAuth covers *"REST APIs and select Git endpoints only"* (no SOAP), and **OAuth/Entra auth is Azure DevOps Services only** — see §10.6.

**Scope inheritance matters for the consent screen.** `vso.work`, `vso.code` and `vso.build` each **inherit `vso.hooks_write`** — you cannot avoid that, and the consent screen will reflect it. Do not request both a scope and its ancestor. Note also that the canonical scopes table lives at `.../authentication/oauth#available-scopes`; the URL `.../authentication/oauth-scopes` **404s**.

**Recommended scope sets:**

| Tier | Scopes |
|---|---|
| Read-only v1 | `vso.profile`, `vso.project`, `vso.work`, `vso.code`, `vso.build`, `vso.release`, `vso.wiki` |
| + Review and comment | add **`vso.threads_full`** (PR comments without the high-privilege `vso.code_write`), `vso.work_write` |
| + Full PR actions | add `vso.code_write` (high privilege: vote, complete, abandon, labels) |
| + Pipeline actions | add `vso.build_execute`, and `vso.release_execute` / `vso.release_manage` for classic deploy/approve |
| + Identity and search | `vso.graph` and/or `vso.identity`; `vso.analytics` for charts; `vso.test` for test summaries |
| Avoid unless essential | `vso.environment_manage` (inherits `vso.agentpools_manage`), `vso.extension_manage`, `user_impersonation` |

### 10.2 Rate limits and throttling

The unit was **renamed** in the 2024–2026 doc refresh: it is now *"Azure DevOps throughput units (TSTUs)"*, not "Team Services Throughput Unit". The acronym stayed.

- One TSTU = *"the average load generated by a typical Azure DevOps user over five minutes."*
- Normal activity spikes at **10 TSTUs or fewer** per five minutes; larger, less frequent spikes reach **100**.
- **The global limit is 200 TSTUs within any sliding five-minute window**, per user per organization. Equivalently, delays begin when *"personal usage exceeds 200 times the consumption of a typical user within a sliding five-minute window."*
- **Pipelines get their own bucket:** 200 TSTU per pipeline per sliding five minutes.
- Delays range from **a few milliseconds up to 30 seconds** per request, stop within five minutes once consumption drops, and *"can continue indefinitely"* if it does not.
- Blocked requests return **HTTP 429** with `TF400733: The request has been canceled: Request was blocked due to exceeding usage of resource <resource> in namespace <namespace>.`
- TSTUs are deliberately abstract: *"You can't calculate usage in TSTUs for an action with a formula."* Consumption of the same operation drifts as an organization grows — **benchmark periodically**.

**Response headers:**

| Header | Meaning |
|---|---|
| `Retry-After` | Seconds to wait before the next request |
| `X-RateLimit-Limit` | Total TSTUs allowed before delays |
| `X-RateLimit-Remaining` | TSTUs remaining; **0 if already delayed or blocked** |
| `X-RateLimit-Reset` | Unix epoch when tracked usage returns to 0 |
| `X-RateLimit-Delay` | How long **this** request was delayed (seconds, ms precision) |
| `X-RateLimit-Resource` | Service and threshold type. *"Threshold types and service names might vary over time and without warning… display this string to a human, but not rely on it for computation."* |
| `X-RateLimit-Cost` | TSTUs consumed by this request. **Use it to find your expensive calls.** |

**All of these except `X-RateLimit-Delay` are sent *before* delays begin** — so a well-behaved client can back off proactively rather than reactively.

**The nastiest gotcha in the entire API surface:** *"Honor the Retry-After header… **The response still returns HTTP 200**, so retry logic isn't required."* **Throttling presents as a slow 200, not a 429.** Your HTTP layer must inspect `Retry-After` and `X-RateLimit-*` on **successful** responses, not only on errors. A client that only checks for 429 will silently degrade to 30-second request latencies with no signal.

**Escape hatch:** assigning the **Basic + Test Plans** access level to the app's identity raises these limits — *"Only the Basic + Test Plans access level provides an increase."* Billed only for the duration assigned.

**The four calls most likely to get you throttled** (per Microsoft's own best-practices page): *"Using queries and individual get work item calls is the top way to get rate limits enforced on your organization."* Batch everything; use the reporting APIs for bulk sync; never poll WIQL in a loop.

### 10.3 Rendering HTML content and embedded images

**This is the single biggest mobile-specific rendering problem.**

Work item HTML fields embed images as `<img src="https://dev.azure.com/{org}/{project}/_apis/wit/attachments/{guid}?fileName=...">`. That is a normal `_apis` route gated by the `vso.work` scope — **not** a pre-signed or anonymous URL. A bare `WebView` or `Image` view sends no `Authorization` header and no Azure DevOps session cookie, so **the images simply fail to load**.

Microsoft does not state this consequence explicitly (so the claim is *verified by behaviour and by the endpoint's declared scope, not by a doc sentence*), but there is a first-party troubleshooting article for the same class of failure in the Visual Studio client, confirming inline work-item images are credential-gated by design.

**Two workarounds, neither documented by Microsoft:**

1. **Intercept and inject.** Android `WebViewClient.shouldInterceptRequest`; iOS `WKURLSchemeHandler` (which requires rewriting to a custom scheme, since `WKWebView` cannot intercept `https`). Match `*/_apis/wit/attachments/*`, re-issue with `Authorization: Bearer <token>`, return the response.
2. **Pre-fetch and inline.** Parse the HTML before rendering, fetch each attachment with the bearer token, and rewrite `src` to a `data:` URI or a local cache-file URL. Safer and more cache-friendly; watch memory, and remember the 60 MB per-attachment ceiling.

The same applies to avatars (§9.1) and to any `_apis`-hosted asset.

One related renderer note: *"External images in markdown might not display if the host doesn't provide the required CORS or CORP headers. The renderer automatically applies `crossorigin="anonymous"` to all external images."*

### 10.4 Markdown support and the format flag

| Milestone | Date | Detail |
|---|---|---|
| Markdown editor for **work item comments** | **May 31, 2023** (preview), GA 2025 | **No opt-out** — *"there is no way to opt-out. Your organization will be onboarded, if not already."* Comments are *"stored as Markdown and returned as Markdown via API. The UI then displays as HTML."* |
| Markdown for **large text fields** | **GA July 7, 2025** | **Opt-in, per work item and per field.** *"By default, all existing and new work items continue using the HTML editor for large text fields."* Depends on the New Boards Hub. |
| Interactive checklists in Markdown fields | Sprint 261, Sept 2025 | *"available in any large text field or comment with Markdown enabled"* |

Fields affected: `System.Description`, Repro Steps, Acceptance Criteria, and custom large-text fields.

**⚠️ The conversion is irreversible:** *"Once you convert a field to Markdown, there's no way to revert it back to HTML."* The same is true per-comment.

**The REST contract is `multilineFieldsFormat` — real, but under-documented.** To *write* Markdown, add a second operation to the JSON Patch document alongside the field value:

```jsonc
[
  { "op": "add", "path": "/fields/System.Description", "value": "# some markdown text" },
  { "op": "add", "path": "/multilineFieldsFormat/System.Description", "value": "Markdown" }
]
```

To *read* the format, the `WorkItem` object exposes `multilineFieldsFormat: {[key: string]: LargeTextCustomHtmlFormat}` — *"Dictionary describing the Format for multiline fields selected by the last edit user."*

**The critical version consequence: this property is present in the `7.2-preview.1` schema and absent from the `7.1` schema.** At `api-version=7.1` you **cannot tell whether `System.Description` is HTML or Markdown**, and will render one as the other. This is the one concrete, well-founded reason to pin `7.2-preview.1` on the work-item read path. Note that `multilineFieldsFormat` appears nowhere in the `wit/work-items` REST *reference* pages — it is documented only in the release blog and the extension-SDK type reference, which is why it is easy to conclude wrongly that no such mechanism exists.

**For comments, the contract is cleaner and separate.** `Comment.format` is a `CommentFormat` enum (`markdown` | `html`), `text` holds the raw content and `renderedText` holds server-rendered HTML. **Request `$expand=renderedText` and render HTML uniformly** — that way the client never has to reimplement Azure DevOps' Markdown dialect. (`renderedTextOnly` exists but the docs mark it as internal.)

**Markdown feature matrix** (from the wiki markdown guidance) — PR comments and wiki are the richest surfaces:

| Feature | PR | Wiki | README | Widget |
|---|---|---|---|---|
| Headers, lists, links, emphasis, quotes | ✓ | ✓ | ✓ | ✓ |
| Tables, images | ✓ | ✓ | ✓ | ✓ |
| Code highlighting | ✓ | ✓ | ✓ | |
| Checklists / task lists | ✓ | ✓ | | |
| Emoji | ✓ | ✓ | | |
| Attachments | ✓ | ✓ | | |
| KaTeX math | ✓ | ✓ | | |
| Suggest change | ✓ | | | |

Renderer constraints to match: **no JavaScript and no iframes**; Mermaid diagrams render in wiki (and, per the 2025 server notes, in repo file previews and PRs); `<u>` and `<font>` work in wiki; `<br/>` in table cells *"works in a wiki but not elsewhere"*; the GitHub emoji set is supported except GitHub Custom Emoji; bare `http`/`https` URLs auto-link in PR comments and wikis; `#123` links a work item; image sizing uses `![alt](./img.png =500x250)`.

**Mentions render in two forms** and your renderer must handle both — `<a href="#" data-vss-mention="version:2.0,{guid}">@Name</a>` in HTML content, and `@<guid>` in Markdown content. `Comment.mentions[]` resolves the GUIDs to identities for you.

### 10.5 Versioning, pagination and batching

**Versioning.** *"API version must be specified with every request."* Format `{major}.{minor}[-{stage}[.{resource-version}]]`. Specify it as `?api-version=7.1` or as `Accept: application/json;api-version=7.1`.

**Preview lifecycle — the rule that should drive your pinning policy:** *"After an API is released (1.0, for example), its preview version (1.0-preview) is deprecated and **can be deactivated after 12 weeks**… Once a preview API is deactivated, requests that specify a `-preview` version get rejected."* **Always pin the exact revision (`7.1-preview.4`), never bare `-preview`**, and put preview endpoints on a watchlist.

**7.1 is GA. 7.2 is preview** — every 7.2 page reads `7.2-preview.N`, and the 7.2 moniker's `defaultMoniker` is still 7.1. Note that "7.1 GA" is **per-endpoint**, not blanket: within 7.1, WIT Comments are `7.1-preview.4`, Graph Users/Groups/SubjectQuery are `7.1-preview.1`, Policy Evaluations are `7.1-preview.1`, Teams–Get All Teams is `7.1-preview.3`, Favorites is `7.1-preview.1`, and Checks and Test Results are `7.1-preview.1`. **Pin per operation, not per client.**

**Pagination has no single pattern.** Continuation-token APIs (Graph, Build, Wiki PagesBatch, PR Commits) return an **opaque** token in the **`X-MS-ContinuationToken` response header** and take it back as a `continuationToken` query parameter — *"The only reliable way to know if there is more data left is the presence of a continuation token."* Do not trim, quote or mutate it, and **URL-encode it** (tokens frequently contain `+`, `/`, `=`). Others use `$top`/`$skip` (Search puts them in the POST **body**). Some mix both (Builds–List). Some have no paging at all (Pipelines Runs–List, Git Items, WIQL). **Projects–List's `continuationToken` is an integer offset**, and the whole Release API uses **int32** tokens. **Default and maximum page sizes are undocumented everywhere — unverified.** Always send an explicit `$top` where supported and always follow the token.

**Batching.** `POST _apis/wit/workitemsbatch` (**max 200**, use `errorPolicy: omit`), `POST .../git/itemsbatch` (metadata only, **response is an array of arrays**, no documented max), `POST .../git/commitsbatch`, `POST .../wiki/pagesbatch`. **There is no OData `$batch` for the core `_apis` REST surface.** `POST _apis/Contribution/HierarchyQuery` is the web UI's internal data-provider RPC — **undocumented, unversioned, unscoped; do not ship against it.**

**Analytics OData** is worth using for charts rather than recomputing aggregates from WIT: `https://analytics.dev.azure.com/{org}/{project}/_odata/{version}/`, scope `vso.analytics`. Versions are `v1.0`, `v2.0`, `v3.0-preview`, `v4.0-preview`; **`v2.0` is the latest released** and is what a shipping app should use — v3.0/v4.0 preview *"might include breaking changes"*. Deprecated versions return **HTTP 410**. It supports `$apply`/`groupby` aggregation, server- and client-driven paging, and its own `$batch` endpoint, and it backs the built-in CFD, lead/cycle time, sprint burndown and velocity reports. Caveat: *"Removing or changing the types of work items or custom fields can cause breaking changes to your model"* — custom fields are not versioned.

### 10.6 Azure DevOps Server (on-premises) parity

**The authoritative mapping table is on the REST reference index, not the versioning concept page** (which is stale and stops at 7.0):

| Server version | REST API version |
|---|---|
| Azure DevOps Server vNext | **7.2** |
| Azure DevOps Server **2022.1** | **7.1** (build ≥ `19.225.34309.2`) |
| Azure DevOps Server 2022 | 7.0 |
| Azure DevOps Server 2020 | 6.0 |
| Azure DevOps Server 2019 | 5.0 |
| TFS 2018 Update 2/3 | 4.1 |

*"REST API versions are compatible with the Server version listed, as well as Server versions that are newer."*

**Naming clarification: there is no product called "Azure DevOps Server 2025."** The current on-premises release is the unversioned **Azure DevOps Server** (internally 25H2): RC October 7 2025, RTW December 9 2025, patches through August 2026. Documentation monikers top out at `azure-devops-server-rest-7.1` — **there is no 7.2 server moniker** — yet the 25H2 release notes explicitly ship some `7.2-preview` properties. Treat on-prem 7.2 as partial and undocumented (*unverified* how broadly).

**Safe on-prem target: `api-version=7.1`** (works on ADS 2022.1 and newer), with 7.0 as the floor for ADS 2022.

**Base URL:** `https://{server}:8080/tfs/{collection}/_apis/...` (default port 8080, default collection `DefaultCollection`).

**What is Services-only:**

| API | On-prem? |
|---|---|
| **Profile** and **Accounts** (`app.vssps.visualstudio.com`) | **No** — Microsoft-hosted SPS host with no on-prem analogue. Zero server monikers. |
| **OAuth 2.0 / Entra ID auth** | **No** — stated twice verbatim: *"available only for Azure DevOps Services, not Azure DevOps Server."* |
| **Graph** (`_apis/graph/*`) | Services-first — no server monikers. On-prem exposes `_apis/identities` (IMS) instead. |
| **Search** (`almsearch`) | Server monikers exist, but on-prem Search is a **separately installed** component on a different host. |
| **Markdown `multilineFieldsFormat`** | 7.2-preview only, so effectively Services-only today. |
| **Pipelines API** | **Yes** — contrary to common belief, server monikers exist through 7.1. |
| WIT, Git, Build, Test, Wiki | **Yes** — full server monikers through 7.1. |
| Analytics OData | **Yes** — auto-installed for new collections on ADS 2020+. |
| Approvals / Environments / Checks | *Unverified.* |

**The big one: a mobile app targeting on-premises has no OAuth option at all.** The docs say to use *".NET client libraries, Windows Authentication, or personal access tokens."* **Budget for an entirely separate auth path — realistically PAT entry — if on-prem is in scope**, plus a separate org-discovery path since Accounts and Profiles do not exist there.

**Citations**

- <https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/integration-bestpractices?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops>
- <https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/>
- <https://devblogs.microsoft.com/devops/new-azure-devops-scopes-now-available-for-microsoft-identity-oauth-delegated-flow-apps/>
- <https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rest-api-versioning?view=azure-devops>
- <https://learn.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.2>
- <https://devblogs.microsoft.com/devops/markdown-support-arrives-for-work-items/>
- <https://learn.microsoft.com/en-us/javascript/api/azure-devops-extension-api/workitem>
- <https://learn.microsoft.com/en-us/azure/devops/project/wiki/markdown-guidance?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/report/extend-analytics/odata-api-version?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/server/release-notes/azuredevopsserver?view=azure-devops>
- <https://learn.microsoft.com/en-us/azure/devops/repos/git/limits?view=azure-devops>

---

## 11. Recommendations for Scoping

### 11.1 Build in this order

1. **Resolve the auth question first.** Entra ID public client + PKCE via MSAL. Confirm whether your target users are Entra-tenant or personal MSA — **if MSA matters, this is a launch blocker, not a detail** (§10.1).
2. **Read-only v1** covering the highest-value, lowest-risk surfaces: work item view + "my work", PR list and PR review (read + comment via `vso.threads_full`), pipeline runs and logs, boards read. All GA at 7.1, all well documented.
3. **Write actions v2:** work item edit and comment, PR vote/complete, Kanban card move, pipeline queue/cancel/retry, approvals.
4. **Notifications last**, and hybrid by design (§6.5) — polling as the default, service hooks as an admin-enabled upgrade.

### 11.2 The five things most likely to hurt

1. **Entra OAuth does not support personal Microsoft accounts for the Azure DevOps resource**, and the fallback platform is closed to new registrations.
2. **No push infrastructure and no inbox API.** A "GitHub Mobile-like" notification experience requires you to build and operate a backend, and service hooks need a project admin per project.
3. **No unified diff endpoint.** The PR review experience — the app's centrepiece — requires a client-side diff engine and a blob cache.
4. **The Comments API is preview** and the discussion view depends on it.
5. **Rate limits present as slow 200s.** Combined with the per-project fan-out needed for a cross-org PR inbox, this is the most likely source of a sluggish app.

### 11.3 Architectural decisions worth locking early

- **Pin api-version per operation**, not per client, and keep an explicit list of preview endpoints under watch.
- **Treat blob SHAs as immutable cache keys** — the single largest performance win in the PR experience.
- **Fetch every `_apis`-hosted asset (attachments, avatars, inline images) through the authenticated HTTP client** and cache locally. Never hand an `_apis` URL to a native image view.
- **Cache identity data keyed on the GUID, never the descriptor** — Microsoft says descriptors rotate.
- **Read `X-RateLimit-Cost` in development** to find your expensive calls before users do.
- **Prefer batch endpoints everywhere**, and use the reporting and Analytics APIs for anything bulk or aggregate.
