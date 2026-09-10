# 05 — Pitfalls, Policy Constraints, and Hard Problems

**Third-party Azure DevOps mobile app (React Native / Expo, iOS + Android, phone + tablet)**

Research date: **2026-09-10**. All statements are sourced to Microsoft Learn / DevBlogs or reputable community sources, with URLs inline. Anything I could not confirm from a primary source is explicitly marked **(unverified)**.

---

## 1. Executive summary

Building a third-party Azure DevOps (ADO) client is *feasible* but the risk profile is dominated by **four structural problems** that are not obvious from the REST API surface:

1. **The authentication platform is mid-migration and has a hole in it.** Azure DevOps OAuth (the legacy first-class 3rd-party app model) stopped accepting new registrations on 2025-04-23 and is slated for full end-of-life in 2026. Its replacement — Microsoft Entra OAuth — **does not natively support Microsoft Account (MSA / personal) users for the Azure DevOps resource**. A new app in 2026 cannot register for the legacy platform and cannot serve MSA-backed organizations via Entra. That is a hard, currently-unresolved product gap.
2. **Org and tenant admins can unilaterally break your app**, and several of the relevant policies are off/restrictive by default. Conditional Access (MFA, device compliance, IP fencing), PAT restriction policies, and third-party OAuth policies all apply and are not negotiable by the app.
3. **There is no push notification path for a third party.** Service hooks require project-level admin permission and are per-project; the Notification API is a *subscription-configuration* API, not an inbox. Any "my activity" feature is polling, and polling collides with the TSTU rate-limit model.
4. **Diffs and boards have no server-side "give me the finished thing" endpoint.** PR diffs must be reconstructed client-side from change metadata + two file fetches per file; board card placement must be reconstructed from per-team `WEF_{guid}_Kanban.*` fields on each work item.

Layered on top: work item schemas are per-project and per-process (so nearly all Boards UI must be data-driven), the HTML→Markdown transition in work item text fields is irreversible and per-field, and MSAL has **no Microsoft-supported React Native SDK**.

### 1.1 Risk register

Likelihood/Impact: L = Low, M = Medium, H = High, VH = Very High.

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | **MSA (personal Microsoft account) users cannot be served.** Entra OAuth doesn't support MSA for the ADO resource; legacy ADO OAuth is closed to new registrations and EOL in 2026. | H (confirmed today) | VH — excludes all `@outlook.com`/`@hotmail.com`-backed orgs, a large share of solo/small-team ADO users | Ship **Entra-only v1**, target Entra-backed orgs. Detect MSA sign-in and show an explicit "not yet supported" screen rather than a broken error. Offer **PAT fallback** as a documented escape hatch (with tenant-policy caveats, R4). Track the "native MSA support through Microsoft Entra OAuth" work item Microsoft says is in progress. |
| R2 | **Org policy "Third-party application access via OAuth" is OFF by default for new orgs.** | H | M (only if you use legacy ADO OAuth) | Do **not** build on legacy ADO OAuth at all. Entra OAuth is explicitly unaffected by this policy. Document this in support material so admins don't chase the wrong toggle. |
| R3 | **Conditional Access blocks the app**: MFA on interactive flow is fine; device-compliance / "require approved client app" / app-protection-policy grants will hard-block a non-Intune-SDK third-party app. | M–H in enterprises | H — silently excludes enterprise customers | Use system browser / ASWebAuthenticationSession + MSAL broker where possible (broker gives device registration + compliance claims). Surface Entra `AADSTS` error codes verbatim with a "show your admin" deep link. Publish an admin doc listing your app's Entra App ID so admins can scope exclusions. Accept that "Require app protection policy" grants are effectively out of reach (R17). |
| R4 | **PAT fallback blocked by tenant/org policy** (restrict PAT creation, restrict full-scoped PATs, max lifespan, global PAT retirement 2026-12-01). | M | M | Never make PAT the only path. Store PAT expiry, warn before it lapses, and support org-scoped (not global) PATs only. |
| R5 | **Rate limiting / TSTU exhaustion from polling.** 200 TSTU per user per sliding 5 min; queries and PR iteration walks are expensive; blocked requests return 429 `TF400733`. | H if naively polled | H — app becomes unusable and the *user's whole ADO session* gets throttled, including their browser | Strict client-side budget; honor `Retry-After` and `X-RateLimit-Delay`; track `X-RateLimit-Cost`; foreground-only polling with backoff; cache aggressively; batch (`workitemsbatch`); never poll from background timers on both platforms simultaneously. See §3. |
| R6 | **No server-side unified diff.** Must fetch both blob versions per file and diff on-device. | Certain | H — perf, memory, and correctness (binary/large/renames) | Client-side diff with a fast JS/native diff (Myers), hard caps (skip >0.5 MB inline, offer download >5 MB, matching web UI thresholds), binary sniffing, `originalPath` for renames, virtualized rendering. See §4. |
| R7 | **Line comments render wrong / detached in the web UI** if `threadContext` + `pullRequestThreadContext.changeTrackingId` are not set correctly. | H on first attempt | M — user-visible data corruption in a shared artifact | Always post with `filePath`, `rightFileStart/End` (line ≥1, offset ≥0), `iterationContext.{first,second}ComparingIteration`, and `changeTrackingId` from the iteration changes list. Verify by reading the thread back. See §4.4. |
| R8 | **Work item forms wrong for custom processes.** Fields, states, rules, pick-lists vary per project/process. | Certain | H — invalid updates, 400s, unhappy users | Fully data-driven forms from `_apis/wit/workitemtypes` + `.../fields/{field}?$expand=All`; cache per project+type with revision checks; always send `test /rev`; use `validateOnly=true` for a dry run before commit. See §5. |
| R9 | **HTML vs Markdown ambiguity in large text fields.** Markdown GA'd 2025-07-07, is opt-in **per field per work item**, and is **irreversible**. | H | M — mangled descriptions, data loss on round-trip | Never round-trip a field you didn't explicitly author. Detect format before editing (`multilineFieldsFormat` — see §5.3, detection mechanism **unverified**); if format is unknown, render read-only or open in web view. Never silently convert HTML→Markdown. |
| R10 | **Board card placement can't be read from the Boards API alone.** Requires per-team `WEF_{guid}_Kanban.Column` / `.Column.Done` / `.Lane` fields on each work item. | Certain | M | Read `boards/{id}` for the schema and `fields.columnField/rowField/doneField` `referenceName`s, then request exactly those fields on the work items. See §6. |
| R11 | **No first-party push for third parties; service hooks need admin.** | Certain | H — "inbox"/notifications is the #1 reason to install a mobile client | v1: foreground polling + local notifications, scoped tightly. v2: optional backend + org-admin-authorized service hooks, sold as a team/enterprise feature. Be explicit in store copy that notifications are best-effort. See §8. |
| R12 | **Apple 4.2 "minimum functionality" rejection** for a thin client over someone else's service. | M | H — no distribution | Native navigation, offline cache, share-sheet/handoff, widgets, biometric lock, tablet layouts, native diff viewer. Avoid WebViews for core flows. See §9.2. |
| R13 | **MSAL has no Microsoft-supported React Native SDK.** | Certain | M–H — auth is the riskiest code in the app | Either (a) `react-native-app-auth` (AppAuth, PKCE, system browser) against Entra v2 endpoints — no broker, so no device-compliance CA; or (b) a community MSAL wrapper (`react-native-msal`) for broker support, accepting unmaintained-dependency risk. Expo requires a **dev client / prebuild** either way — this is not Expo Go compatible. See §7.4 and §9.4. |
| R14 | **Legacy ADO OAuth full EOL in 2026** (exact date not published). | Certain | VH *if* you depend on it | Don't. Entra-only. |
| R15 | **Public projects retired; existing public projects convert to private in 2027**; anonymous access permanently disabled. | Certain | L–M | Drop any "browse public projects unauthenticated" feature. Require auth everywhere. |
| R16 | **Trademark / naming rejection or takedown** ("Azure DevOps" in app name or icon). | M | M | Distinct brand name; use only a truthful compatibility statement ("works with Azure DevOps") in the description body, not in the app name or icon. See §9.1. |
| R17 | **Intune App Protection Policy CA grant excludes the app** (would require Intune App SDK integration). | M in regulated enterprises | M — a named enterprise segment is unreachable | Treat as out of scope for v1–v2; document the limitation. Revisit only with a concrete enterprise contract funding Intune SDK work. |
| R18 | **On-prem Azure DevOps Server support** (self-signed certs, NTLM, version-skewed APIs). | M (users will ask) | M — large hidden cost | **Defer.** NTLM is being removed from libcurl in Sept 2026 anyway. See §10. |
| R19 | **API version churn / preview API deactivation** (preview APIs deactivatable 12 weeks after GA of that version). | M | M | Pin `api-version=7.1` (GA) everywhere; never ship a `-preview` dependency in a released build; centralize the version constant. |
| R20 | **Token theft from device / insecure storage.** | L–M | VH — reputational, plus enterprise trust | Keychain / Android Keystore via `expo-secure-store` or `react-native-keychain`; biometric gate; never log tokens; no tokens in analytics/crash reports; short-lived access token + refresh token only. |
| R21 | **Google Play Data safety mis-declaration** (removal from Play). | M | H | Complete the form honestly for all 14 categories; publish a privacy policy; note that ADO content stays on-device and is not transmitted to your servers (if that's true — it *isn't* if you build the R11 v2 backend). |
| R22 | **Guest / B2B and multi-tenant users** see wrong or partial org lists; token audience/tenant mismatch. | H | M | Per-org token cache keyed by tenant; use `app.vssps.visualstudio.com/_apis/accounts?memberId=` for org discovery; handle per-tenant re-auth. See §7. |
| R23 | **Work item revision limit (10,000 via REST) and link limits.** | L | L–M | Batch field changes into a single PATCH; never chatty per-field updates. |
| R24 | **WIQL result truncation at 20,000 with no error**, and 30-second query timeout (`VS402335`). | M | M | Always scope by project + date range; page with `$top`; use reporting APIs for bulk, never queries. |

---

## 2. Organization- and tenant-level security policies

Primary source: [Change application connection and security policies for organizations](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/change-application-access-policies?view=azure-devops) (doc updated 2025-10-10).

### 2.1 Policy inventory, level, and default

| Policy | Level | Default | Affects Entra OAuth tokens? | Affects PATs? | Affects legacy ADO OAuth? |
|---|---|---|---|---|---|
| **Third-party application access via OAuth** | Org (PCA) | **OFF for all new organizations**; existing orgs allow all auth methods by default | **No** — doc says explicitly "This policy doesn't affect Microsoft Entra ID OAuth app access" | No | **Yes — blocks it** |
| **SSH authentication** | Org (PCA) | On (existing orgs) | No | No | No |
| **Validate SSH key expiration** | Org (PCA) | **Enabled by default**; expired keys immediately invalid | No | No | No |
| **Log audit events** | Org (PCA) | Off unless enabled | Indirect (auditing only) | Indirect | Indirect |
| **Restrict personal access token creation** | Org (PCA) | Off; sub-policies allow packaging-only PATs or allowlisted Entra users/groups | No | **Yes** | No |
| **Allow public projects** | Org (PCA) | Being retired — see §11 | No | No | No |
| **Additional protections when using public package registries** | Org (PCA) | n/a to this app | — | — | — |
| **Enable IP Conditional Access policy validation on non-interactive flows** | Org (PCA) | Off unless enabled | **Yes** (non-interactive REST) | **Yes** | Yes |
| **External guest access** | Org (PCA) | Varies | Indirect (who can be a member) | Indirect | Indirect |
| **Allow team and project administrators to invite new users** | Org (PCA) | On | No | No | No |
| **Request access** | Org (PCA) | On | No | No | No |
| **Restrict organization creation** | **Tenant** (Azure DevOps Administrator) | Off | No | No | No |
| **Restrict global personal access token creation** | **Tenant** | Off | No | **Yes** | No |
| **Restrict full-scoped personal access token creation** | **Tenant** | Off | No | **Yes** | No |
| **Enforce maximum personal access token lifespan** (days) | **Tenant** | Off | No | **Yes** | No |

Verified points worth restating verbatim:

> "**Third-party application access through OAuth**: … This policy is defaulted to *off* for all new organizations. … This policy doesn't affect Microsoft Entra ID OAuth app access."

So the widely-repeated claim in the brief is **confirmed**: default-off since the 2023-era change for new orgs, blocks *Azure DevOps* OAuth apps only, and **Entra ID OAuth tokens are unaffected**. This is a strong argument for going Entra-only regardless of R1.

PAT policy detail: [Manage PATs using policies](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/manage-pats-with-policies-for-administrators?view=azure-devops). Tenant policies apply only to **new** PATs; existing non-compliant PATs keep working until renewal, at which point they must be brought into compliance. Admins can add Entra users/groups as exemptions.

### 2.2 Conditional Access

Primary source: [Conditional Access policies on Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops) (updated 2026-03-03).

- The CA target resource is **"Azure DevOps" / "Microsoft Visual Studio Team Services", resource ID `499b84ac-1321-427f-aa17-267ca6975798`**.
- **Interactive (web/browser) flows**: after Microsoft modernized ADO's web auth stack to Entra tokens, **all CA policies are validated on all interactive flows** — MFA, device compliance, location, etc. Your OAuth sign-in runs through this.
- **Non-interactive flows** (REST with a PAT, background token refresh): MFA policies are enforced on web flows only; non-interactive flows are **blocked** if the user doesn't meet a policy. IP-fencing CA is enforced on non-interactive flows **only if the org enables "Enable IP Conditional Access policy validation on non-interactive flows"** (PCA permission required). Supports IPv4 and IPv6; the doc warns explicitly about VPN split-tunnel cases where the Entra sign-in IP differs from the ADO request IP.
- **Continuous Access Evaluation (CAE)** is supported: tokens can be revoked near-real-time on user disable, password change, or location/IP shift. **Your client must handle claims challenges gracefully** — a `WWW-Authenticate` claims challenge means re-acquire the token interactively with the challenge, not "log the user out". Microsoft's guidance: [Claims challenges](https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge).
- **ARM audience change (Sept 2025)**: Azure DevOps no longer requires the Azure Resource Manager audience during sign-in/refresh. If an admin previously relied on an ARM CA policy to cover ADO, that coverage is gone; a dedicated ADO CA policy is needed. Reference: [Removing Azure Resource Manager reliance on Azure DevOps sign-ins](https://devblogs.microsoft.com/devops/removing-azure-resource-manager-reliance-on-azure-devops-sign-ins/).

**Mitigations for a mobile client**

- Sign in through the **system browser** (ASWebAuthenticationSession / Custom Tabs), never an embedded WebView — embedded WebViews break SSO, break device-compliance evaluation, and are increasingly blocked by Entra.
- Implement **CAE claims-challenge handling** end-to-end (401 + `WWW-Authenticate: Bearer claims="..."` → interactive re-auth with `claims` param).
- Surface the raw `AADSTS…` code and the Entra error message; add a "Copy diagnostics for your admin" action.
- Publish your app's **Entra Application (client) ID** in your docs so tenant admins can create a targeted exclusion or grant admin consent.
- Detect IP-CAP failures (which look like generic 401/403 on REST but not on sign-in) and explain "your organization restricts API access by network location".

---

## 3. Rate limiting and throttling

Primary sources: [Rate and usage limits](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops) (updated 2025-09-15) and [Integration best practices](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/integration-bestpractices?view=azure-devops) (updated 2026-03-02).

### 3.1 The model (verified)

- Consumption is measured in **TSTUs (Azure DevOps throughput units)** — an intentionally abstract blend of Azure SQL DTUs, app-tier CPU/memory/IO, and Azure Storage bandwidth. Currently weighted heavily toward SQL DTUs.
- **1 TSTU ≈ the average load of a typical ADO user over five minutes.**
- Normal activity spikes ≤ 10 TSTU / 5 min; larger occasional spikes up to 100.
- **Global limit: 200 TSTU in any sliding five-minute window, per user.** The same 200 TSTU / 5 min limit applies per *pipeline*.
- **Two distinct behaviors:**
  - **Delay** — requests are slowed from a few milliseconds up to **30 seconds each**, and the response is still **HTTP 200**. There is no error to retry on. Delays stop within five minutes of consumption dropping, but can continue *indefinitely* if consumption stays high.
  - **Block** — **HTTP 429** with `TF400733: The request has been canceled: Request was blocked due to exceeding usage of resource <resource> in namespace <id>.`
- Significant delays generate an **email to the user and a warning banner in the ADO web UI**. From a product standpoint this is severe: a badly-behaved mobile client gets the *user* a scary email from Microsoft.
- Higher limits are available only by assigning the identity the **Basic + Test Plans** access level — irrelevant for an end-user client.

### 3.2 Headers (verified, complete list)

| Header | Meaning |
|---|---|
| `Retry-After` | RFC 6585 seconds to wait. **Sent with HTTP 200 responses during the delay phase**, not only with 429. |
| `X-RateLimit-Resource` | Service + threshold type reached. Display to humans; do not parse. |
| `X-RateLimit-Delay` | Seconds (3 dp) this request was delayed. **The only header sent *after* delays begin.** |
| `X-RateLimit-Limit` | Total TSTUs allowed before delays. |
| `X-RateLimit-Remaining` | TSTUs remaining before delays start; `0` once delayed/blocked. |
| `X-RateLimit-Reset` | Unix epoch when tracked usage would return to 0 if all consumption stopped. |
| `X-RateLimit-Cost` | TSTUs consumed by *this* request (5 dp), when present. **This is the instrumentation hook you want.** |

### 3.3 Expensive calls to watch

Microsoft does not publish per-endpoint TSTU costs (they say you can't compute TSTUs by formula; you must observe them on the [usage monitoring](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/usage-monitoring?view=azure-devops) page). Documented cost drivers:

- **WIQL queries** — explicitly called out: "Using queries and individual *get work item* calls is the top way to get rate limits enforced on your organization." Query cost scales with the number of work items searched and grows as the org grows. 30-second server timeout → `VS402335`.
- **PR iteration changes walks** — each iteration + each file version fetch is a separate request; a 200-file PR reviewed across 5 iterations is easily 400–1000 requests if done naively.
- **Version control file content fetches** — storage bandwidth counts toward TSTUs.
- Query anti-patterns to avoid (from the best-practices doc): `Ever`, `Contains` on long text, `<>`/`Not`, `In Group` on large groups, many `Or`s, `OR` between `In Group` and Area/Iteration path, sorting on non-core fields, and unscoped cross-project queries.

Hard limits worth encoding as constants:

- **WIQL results truncate at 20,000 items with no error shown** ([work tracking limits](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops)).
- **Work item revision limit of 10,000 for updates made through the REST API** (web portal exempt).
- PR iteration changes: `$top` default **100**, max **2000**; page via `nextSkip` / `nextTop`.

### 3.4 A polling budget that survives

Target: **≤ ~20 TSTU per 5-minute window** in steady state — 10% of the ceiling — leaving headroom for the user's browser session on the same identity.

Concrete design:

1. **Never poll in the background on a timer.** iOS BGAppRefresh and Android WorkManager both fire unpredictably and will multiply across a user's devices. Poll on: app foreground, pull-to-refresh, and a single foreground timer (≥ 60 s) while a screen is visible.
2. **One composite refresh, not N screen refreshes.** A single "inbox" sync should be ~3–5 requests, not one per project:
   - PRs where I'm a reviewer: `GET .../_apis/git/pullrequests?searchCriteria.reviewerId={id}&searchCriteria.status=active&$top=50` (org-scoped, one call).
   - PRs I created: same endpoint with `searchCriteria.creatorId`.
   - Work items assigned to me / recently changed: **one** org-wide WIQL scoped by date, e.g. `WHERE [System.AssignedTo] = @Me AND [System.ChangedDate] >= @Today - 14`, then a single `POST _apis/wit/workitemsbatch` with an explicit `fields` list for the returned IDs. Batch, don't loop.
   - Builds: `GET .../_apis/build/builds?minTime=...&$top=25` per pinned project only.
3. **Delta-only.** Persist a `lastSyncUtc` per feed and always filter server-side by changed-date. Never re-pull a full list.
4. **Explicit field projection.** Always send `fields=` on work item batch calls; never `$expand=all`. Payload size feeds storage-bandwidth TSTUs.
5. **Adaptive backoff driven by headers.** Maintain a rolling estimate from `X-RateLimit-Cost`; if `X-RateLimit-Remaining` drops below ~25% of `X-RateLimit-Limit`, double the poll interval; if `X-RateLimit-Delay` or `Retry-After` appears, stop scheduled polling entirely for `Retry-After` seconds and show a subtle "syncing paused" chip. On 429 `TF400733`, exponential backoff with jitter starting at 60 s.
6. **Single-flight + coalescing.** De-duplicate concurrent identical requests; cancel in-flight requests on screen dismissal.
7. **Cache with a TTL ladder.** Immutable data (blob content by `objectId`, commit metadata, completed PR iterations, closed work item revisions) → cache forever on disk. Semi-static (work item type definitions, board configuration, repo lists, team lists) → 24 h with background revalidation. Live (PR list, thread list, build status) → 60 s.
8. **Instrument it.** Log `X-RateLimit-Cost` per endpoint to your own telemetry (never with tokens) so you learn your real cost profile — Microsoft's docs say costs shift as orgs grow, so this must be measured, not assumed.

---

## 4. Diff and PR review: the hard problems

### 4.1 There is no server-side unified diff (verified)

Neither of the two candidate endpoints returns diff hunks or patch text:

- **`GET .../pullRequests/{id}/iterations/{n}/changes`** ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get?view=azure-devops-rest-7.1)) returns `changeEntries[]` of `{ changeId, changeTrackingId, changeType, item: { objectId, originalObjectId, path }, originalPath, sourceServerItem, url }`. `newContent` exists on the type but is not populated for reads — it is the *push* shape. There is `$compareTo={iteration}` to diff two iterations, `$top` (default 100, max 2000), `$skip`, and `nextSkip`/`nextTop` for paging.
- **`GET .../_apis/git/repositories/{repoId}/diffs/commits?baseVersion=&targetVersion=`** ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/diffs/get?view=azure-devops-rest-7.1)) returns a `GitCommitDiffs` object: change counts, the changed-item list, and the common ancestor (merge base). **Still metadata only.** There is no `.diff`/`.patch` media type. Community confirmation: [Compare two commits and get response in .diff format](https://techcommunity.microsoft.com/discussions/azure/compare-two-commits-using-azure-devops-api-and-get-response-in--diff-format/3248983) — the answer is "you can't; fetch both versions".

**Consequence:** for each changed file you need **two** additional requests (base blob + target blob) via
`GET .../_apis/git/repositories/{repoId}/items?path={path}&versionDescriptor.version={objectId}&versionDescriptor.versionType=commit&includeContent=true&$format=text`
(or `.../blobs/{objectId}`), then run the diff on-device.

**Mitigations**

- Diff on demand, one file at a time, driven by the file the user opened — never pre-diff the whole PR.
- Blobs are content-addressed by `objectId`, so they are **perfectly cacheable forever**. A per-repo LRU keyed by `objectId` eliminates almost all re-fetches across iterations.
- Use a proven diff implementation; run it off the JS thread (a worklet, `react-native-worklets`, or a small Rust/C++ turbomodule) for files over a few thousand lines.
- Pre-compute and cache the hunk list; render with a virtualized list (`FlashList`) at hunk granularity, expanding context lazily.

### 4.2 Size, binary, and rename edge cases (verified thresholds from the web UI)

From [Review and comment on pull requests](https://learn.microsoft.com/en-us/azure/devops/repos/git/review-pull-requests?view=azure-devops) (updated 2026-09-08) — mirror these thresholds so behavior matches the web:

- **The summary view does not show changes for a file larger than 0.5 MB.**
- **For any single file larger than 5 MB, the diff view shows truncated content**; the docs tell users to download and use a local diff tool.
- **Git treats a file as *renamed* when it has more than 50% changes. This threshold is the Git default and cannot be changed.**

Additional handling you must implement yourself:

- **Binary detection**: ADO does not flag binary in `changeEntries`. Sniff: NUL byte in the first 8 KB, or a non-UTF-8 decode failure, or an extension allowlist. Render "Binary file — X KB" with an image preview for known image types (fetched with auth, see §5.6).
- **Renames**: `changeType: "rename"` (also `sourceRename`/`targetRename`) with `originalPath` set. Render as `old → new`, and only diff content if `objectId != originalObjectId`.
- **Encoding / EOL**: `changeType: "encoding"` exists as a distinct change type; CRLF↔LF-only diffs are a common noise source. Offer a "ignore whitespace/EOL" toggle computed client-side.
- **Deletes/adds**: only one side has an `objectId`; don't attempt a two-sided fetch.

### 4.3 Iterations and "what's new since I last looked"

- Iteration 1 is the head of the source branch at PR creation; each push creates a new iteration.
- `$compareTo` gives you exactly the "changes since iteration N" view the web UI's changeset dropdown shows.
- Force-pushes: the **Updates** tab (iterations) preserves history even across force-push, while the **Commits** tab is overwritten. If you show "commits", warn that it can change under the user.

### 4.4 Posting a line comment that renders correctly

Verified from [Pull Request Threads – Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/create?view=azure-devops-rest-7.1).

```http
POST https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads?api-version=7.1
Content-Type: application/json

{
  "comments": [
    { "parentCommentId": 0, "content": "Should we add a comment about what this value means?", "commentType": 1 }
  ],
  "status": 1,
  "threadContext": {
    "filePath": "/new_feature.cpp",
    "leftFileStart": null,
    "leftFileEnd": null,
    "rightFileStart": { "line": 5, "offset": 1 },
    "rightFileEnd":   { "line": 5, "offset": 13 }
  },
  "pullRequestThreadContext": {
    "changeTrackingId": 1,
    "iterationContext": { "firstComparingIteration": 1, "secondComparingIteration": 2 }
  }
}
```

Rules that matter:

- **`filePath` is repo-root-relative and starts with `/`.**
- **`CommentPosition.line` starts at 1; `offset` starts at 0.** (Doc: "The line number of a thread's position. Starts at 1." / "The character offset … Starts at 0.") An off-by-one here silently anchors the comment to the wrong line.
- Comment on the **right** file (`rightFileStart/End`) for added/changed lines; use `leftFileStart/End` for deleted lines. Setting both spans a change.
- **`changeTrackingId` — the doc is explicit: "Used to track a comment across iterations. This value can be found by looking at the iteration's changes list. *Must be set for pull requests with iteration support.*"** Take it from the `changeEntries[].changeTrackingId` of the iteration you rendered. Omitting it is the single most common cause of comments that appear "outdated"/detached after the next push.
- `iterationContext.firstComparingIteration` == `secondComparingIteration` means the left side is the merge base.
- On read, `pullRequestThreadContext.trackingCriteria` (with `origFilePath`, `origLeft*`, `origRight*`) tells you the thread was **tracked** from an earlier position — you must render at the *tracked* position for the current iteration, not the original one, or your UI will disagree with the web.
- Enums: `CommentThreadStatus` = `unknown | active | fixed | wontFix | closed | byDesign | pending` (note **`byDesign`** and **`fixed`**, not "resolved" — the web UI label "Resolved" maps to `fixed`). `CommentType` = `unknown | text | codeChange | system`. Post `commentType: 1` (`text`).
- Replies: `POST .../threads/{threadId}/comments` with `parentCommentId` set.
- Scopes: `vso.code_write` or `vso.threads_full`.

**Verify-by-read-back**: after creating a thread, GET it and assert `threadContext.filePath` and the resolved line — cheap insurance against silent mis-anchoring.

### 4.5 Suggested changes — **correction to the brief**

The premise "ADO has no suggestion feature like GitHub" is **false as of 2026**. From the official doc ("Suggest changes in comments"):

> "Select the light bulb icon under the comment box to make your suggested changes in the comment box within a **fenced code block**… You don't see a light bulb icon if you add a comment to the original code (left-hand side) of a side-by-side diff view."

Authors then use **Apply changes** (stage) → **Commit all changes**, with **Undo change** to unstage. So suggestions exist, work per-line and per-line-range, and are author-applyable in the web UI.

**What is unverified:** the exact on-the-wire representation. The REST `Comment` object has only `content` (string) — there is no `suggestion` field — so the suggestion must be encoded in the Markdown content of the comment plus the thread's line span. The GitHub-style ` ```suggestion ` fence is the strong hypothesis and is what community tooling (e.g. PR-Agent's Azure DevOps provider) emits, and there are open issues about ADO suggestion formatting: [qodo-ai/pr-agent#2110](https://github.com/qodo-ai/pr-agent/issues/2110). **Mark as (unverified) and confirm empirically**: create a suggestion in the web UI on a scratch PR, then `GET .../threads` and inspect the raw `content`. Do this before designing the mobile suggestion composer.

### 4.6 Vote semantics (verified)

REST values on `IdentityRefWithVote.vote` ([Pull Request Reviewers – Create/Update](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-reviewers/create-pull-request-reviewer?view=azure-devops-rest-7.1)) and their UI labels:

| Value | REST meaning | Web UI label | Blocks approval when set by a *required* reviewer? |
|---|---|---|---|
| `10` | approved | **Approve** | No |
| `5` | approved with suggestions | **Approve with suggestions** | No |
| `0` | no vote | **Reset feedback** | No — absence of a vote does not prevent completion |
| `-5` | waiting for author | **Wait for author** | **Yes** |
| `-10` | rejected | **Reject** | **Yes** |

`PUT .../pullRequests/{id}/reviewers/{reviewerId}` to cast; `PATCH .../reviewers` to reset multiple. Mobile UX note: `-5` and `-10` are destructive-ish social actions; require a confirmation and encourage an accompanying comment (the docs say to add a comment explaining a Reject).

Also relevant: **GitHub Copilot code review is now available in ADO PRs (public preview)** and "always leaves a **Comment** review, so its feedback doesn't satisfy required-reviewer policies and doesn't block merging." Your reviewer list UI will encounter a Copilot pseudo-identity — don't assume all reviewers are humans with avatars.

### 4.7 Branch policies, required reviewers, and completion

- Policies live under `_apis/policy/configurations` ([Policy REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/policy/?view=azure-devops-rest-7.1)) and are per-repo/per-branch. The PR object exposes evaluated status; use `_apis/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/{projectId}/{prId}` to render "what's blocking this PR" — this is what makes a mobile PR screen genuinely useful.
- Required reviewers added by policy **cannot be made optional or removed** by the PR author; your UI must not offer that affordance for policy-added reviewers.
- **Completion** (`PATCH .../pullrequests/{id}` with `status: "completed"`, `lastMergeSourceCommit`, and `completionOptions`). `GitPullRequestCompletionOptions` fields: `mergeStrategy` (`noFastForward` | `squash` | `rebase` | `rebaseMerge`), `deleteSourceBranch`, `mergeCommitMessage`, `squashMerge` (deprecated), `bypassPolicy` + `bypassReason`, `transitionWorkItems`, `autoCompleteIgnoreConfigIds`, `triggeredByAutoComplete`. Docs: [Complete, abandon, or revert PRs](https://learn.microsoft.com/en-us/azure/devops/repos/git/complete-pull-requests?view=azure-devops), [Merge strategies](https://learn.microsoft.com/en-us/azure/devops/repos/git/merging-with-squash?view=azure-devops), [GitPullRequestCompletionOptions](https://learn.microsoft.com/en-us/javascript/api/azure-devops-extension-api/gitpullrequestcompletionoptions).
- **If `mergeStrategy` is unset, the service picks the first strategy not prohibited by the target branch's policy** (default `noFastForward` when no limit-merge-type policy exists). Mobile clients should read the branch's merge-type policy and only offer allowed strategies — offering a blocked strategy produces a confusing 400.
- **Auto-complete** (`autoCompleteSetBy`) is the right mobile primitive: set auto-complete from the phone, let policies land it. Note ADO shipped "auto-complete PRs by default" in [Sprint 270 (2026)](https://learn.microsoft.com/en-us/azure/devops/release-notes/2026/sprint-270-update) — verify default behavior so your toggle reflects reality.
- `bypassPolicy: true` requires elevated permission and is a genuinely dangerous button on a phone. Gate it behind a typed confirmation or omit it in v1.
- **PR review is browser-only per Microsoft's own docs** ("You can only review Azure DevOps PRs in the web portal by using your browser"). That's a statement about first-party surfaces, not an API restriction — but it is also the market gap your app fills, and worth quoting in positioning.

---

## 5. Work item complexity

### 5.1 Process templates make everything dynamic

Projects use Basic, Agile, Scrum, CMMI, or an **inherited custom process** derived from those. Field sets, states, state categories, workflow rules, and even *which* work item types exist vary per project. There is no safe hardcoding.

Required metadata calls (cache aggressively — this is 24 h TTL data):

| Purpose | Endpoint |
|---|---|
| Types in a project | `GET {org}/{project}/_apis/wit/workitemtypes?api-version=7.1` |
| One type (incl. states, transitions, field list, icon, color) | `GET {org}/{project}/_apis/wit/workitemtypes/{type}?api-version=7.1` |
| States for a type | `GET {org}/{project}/_apis/wit/workitemtypes/{type}/states?api-version=7.1` |
| **Field rules + pick-lists** | `GET {org}/{project}/_apis/wit/workitemtypes/{type}/fields/{field}?$expand=All&api-version=7.1` |
| All fields in the org | `GET {org}/_apis/wit/fields?api-version=7.1` |
| Process definitions (inherited processes) | `GET {org}/_apis/work/processes/...` ([Work Item Tracking Process API](https://learn.microsoft.com/en-us/rest/api/azure/devops/processes/?view=azure-devops-rest-7.1)) |
| Process configuration (backlog levels, board mappings) | `GET {org}/{project}/_apis/work/processconfiguration?api-version=7.1` |

`WorkItemTypeFieldWithReferences` (verified from [Work Item Types Field – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-types-field/get?view=azure-devops-rest-7.1)) returns:

- `alwaysRequired` (boolean)
- `defaultValue`
- `allowedValues[]` — for identity fields these are objects with `displayName`, `id`, `uniqueName`, `descriptor`; for pick-lists, strings
- `dependentFields[]` — `WorkItemFieldReference[]`, i.e. **conditional rules exist and must be re-evaluated when a dependency changes**
- `helpText`, `name`, `referenceName`, `url`

`$expand` levels: `none | allowedValues | dependentFields | all`.

**Important gap:** `alwaysRequired` and `dependentFields` do **not** express the full rules engine. Conditional required/read-only rules ("when State = Closed then Reason is required", custom rules from an inherited process) are only fully enforced server-side. Reference: [Default rule reference](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/rule-reference?view=azure-devops).

**Mitigation:** treat the server as the source of truth. Use `validateOnly=true` on a PATCH to get the rules engine's verdict *before* you commit, and render the returned message. This is the single best trick for a mobile work item editor.

### 5.2 Update semantics, concurrency, and error handling (verified)

```http
PATCH https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.1
     [&validateOnly={bool}][&bypassRules={bool}][&suppressNotifications={bool}][&$expand={None|Relations|Fields|Links|All}]
Content-Type: application/json-patch+json

[
  { "op": "test", "path": "/rev", "value": 3 },
  { "op": "add",  "path": "/fields/System.State", "value": "Active" },
  { "op": "add",  "path": "/fields/System.AssignedTo", "value": "user@contoso.com" }
]
```

- **Optimistic concurrency is the `test` op on `/rev`**, not `If-Match`/ETag. If the work item moved, the whole patch fails and you must re-read, show a merge/conflict UI, and retry. **Always include it** — a mobile app is guaranteed to have stale state.
- `validateOnly=true` — dry-run against the rules engine.
- `bypassRules=true` — requires the project-level "Bypass rules on work item updates" permission; do not expose it in a general-purpose client.
- `suppressNotifications=true` — useful for background/system-ish edits; do not use for user-initiated edits (it would silently deprive teammates of notifications).
- Media type **must** be `application/json-patch+json`.
- **Batch field changes into one PATCH.** The best-practices doc: "Reduce your updates by batching your field changes. Don't update just one field at a time," plus the **10,000-revision REST limit** and a warning that link limits will be enforced.
- Errors come back as HTTP 400 with a `VS`-prefixed message (e.g. `VS402335` for query timeouts). **(unverified)** I could not find a published, stable catalog of work-item rule-violation error codes; treat messages as human-readable strings, surface them verbatim next to the offending field where the message names a field, and never try to parse them into structured logic.
- Multi-item read: `POST {org}/_apis/wit/workitemsbatch` with `{ ids, fields, $expand }` — up to 200 ids per call. Use this everywhere instead of N `GET`s.

### 5.3 HTML vs Markdown in large text fields

Timeline (verified): private preview during 2024–2025 ([Markdown for large text fields (private preview)](https://devblogs.microsoft.com/devops/markdown-for-large-text-fields-private-preview/)); **GA 2025-07-07**, rolled out in five waves over 4–5 weeks ([Markdown Support Arrives for Work Items](https://devblogs.microsoft.com/devops/markdown-support-arrives-for-work-items/)). Earlier, comments got an HTML/Markdown toggle in [Sprint 231 (2023)](https://learn.microsoft.com/en-us/azure/devops/release-notes/2023/sprint-231-update).

Verified API shape:

```json
[
  { "op": "add", "path": "/fields/System.Description",        "value": "# some markdown text" },
  { "op": "add", "path": "/multilineFieldsFormat/System.Description", "value": "Markdown" }
]
```

- Applies to **any** large text field: `System.Description`, `Microsoft.VSTS.TCM.ReproSteps`, `Microsoft.VSTS.Common.AcceptanceCriteria`, and custom HTML fields.
- **Default is `HTML`.**
- **Irreversible: "Once a work item is saved with `Markdown`, it cannot be reverted back to `HTML`."** It is per-field, per-work-item.
- Pasting HTML into a Markdown-mode editor triggers auto-conversion to Markdown.

**Detection is the problem.** The GA blog does not document how to read a field's current format. **(unverified)** The likely mechanism is a `multilineFieldsFormat` map returned on `GET _apis/wit/workitems/{id}` (possibly under `$expand`), mirroring the write path. **Action: confirm empirically before writing the editor** — create two work items in a scratch project, convert one field to Markdown, and diff the raw JSON of `GET` responses.

**Mitigations regardless of detection outcome:**

- **Never round-trip content you didn't author.** If you must edit an existing description, edit *within* the detected format; if format is unknown, open the field read-only with a "Edit in browser" deep link.
- Do not implement your own HTML↔Markdown converter for save paths — an accidental conversion is permanent and destroys the team's data.
- Rendering: you must support **both** an HTML renderer (sanitized) and a Markdown renderer, and they must look consistent. Sanitize aggressively — work item HTML is user-authored and arrives from an authenticated context.

### 5.4 Identity fields

- Values historically serialize as **`"Display Name <unique.name@contoso.com>"`** in string form, and as an `IdentityRef` object in structured form. Accept both on read; on write, the `uniqueName`/UPN or the identity `id` is safest.
- Allowed values for identity fields come from `.../fields/{field}?$expand=All` as objects with `displayName`, `id`, `uniqueName`, `descriptor` — but for large orgs this list is impractical. Use the **identity picker** flow instead: `POST {org}/_apis/IdentityPicker/Identities` **(unverified — this is a widely used but lightly documented endpoint; validate before depending on it)**, or Graph users search (§7.3).
- `IdentityRef` has several **deprecated** members you should not build on: `imageUrl` (use the `avatar` entry in `_links`), `uniqueName` (use Domain+PrincipalName), `directoryAlias`, `isAadIdentity`, `isContainer`, `profileUrl`, `inactive`.

### 5.5 Attachments

- Upload: `POST {org}/{project}/_apis/wit/attachments?fileName={name}&api-version=7.1` with the binary body → returns an attachment URL/id. Then `PATCH` the work item with a `relations` `add` op of `rel: "AttachedFile"`. Docs: [Attachments – Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/create?view=azure-devops-rest-7.1).
- Two-step means partial failure is possible (uploaded blob, unattached). Make the composer idempotent and retryable.
- Mobile: use a background upload (`expo-file-system` upload task / native URLSession background session) so large photo attachments survive backgrounding.

### 5.6 Embedded images in HTML fields need authentication

Work item HTML contains `<img src="https://dev.azure.com/{org}/{project}/_apis/wit/attachments/{guid}?fileName=...">`. **These URLs require the Authorization header.** A plain `<Image source={{uri}}>` or a WebView will render a broken image, because neither carries your bearer token by default.

**Mitigations:**

- Pre-process the HTML: extract attachment URLs, fetch each with auth into the app's cache directory, and rewrite `src` to a local `file://` URI before rendering.
- Or use an image component that accepts headers (`expo-image` supports `source: { uri, headers }`; `react-native-fast-image` supports headers) — but a WebView-rendered HTML body cannot, so pre-processing is the robust answer.
- Cache by attachment GUID (immutable) — these are free to cache forever.

### 5.7 Tags

`System.Tags` is a single semicolon-separated string (`"tag1; tag2"`). To add/remove you rewrite the whole string, which is a lost-update hazard on a phone — the `test /rev` op is essential here. Existing org tags: `GET {org}/{project}/_apis/wit/tags?api-version=7.1-preview` **(preview — see R19; treat as best-effort autocomplete, degrade to free text)**.

---

## 6. Board reconstruction

### 6.1 What the Boards API gives you (verified)

`GET {org}/{project}/{team}/_apis/work/boards/{id}?api-version=7.1` ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/work/boards/get?view=azure-devops-rest-7.1)) returns a `Board`:

- `columns[]` → `BoardColumn { id, name, columnType, description, isSplit, itemLimit, stateMappings }`
  - `columnType` ∈ `incoming | inProgress | outgoing`
  - `isSplit` = the **Doing/Done split column** flag
  - `itemLimit` = **WIP limit** (0 = unlimited)
  - `stateMappings` = map of work item type → state, i.e. **column names are not states**; the mapping is per-type
- `rows[]` → `BoardRow { id, name, color }` = **swimlanes** (the default lane typically has a null/empty name)
- `fields` → `BoardFields { columnField, rowField, doneField }`, each a `FieldReference { referenceName, url }`
- `allowedMappings`, `canEdit`, `isValid`, `revision`

`{id}` may be the backlog level name (e.g. `"Stories"`, `"Features"`, `"Epics"`) or a GUID. `GET .../_apis/work/boards` lists them. Backlog levels themselves come from `_apis/work/processconfiguration` and `_apis/work/backlogs`.

### 6.2 Why that isn't enough

The `Board` describes the *schema*, not *where each card sits*. Per-card placement lives in **team-scoped work item fields** whose reference names are exactly the `fields.columnField/rowField/doneField` values, and which look like:

- `WEF_{32-hex-guid}_Kanban.Column` — the column name
- `WEF_{32-hex-guid}_Kanban.Column.Done` — boolean, the Done half of a split column
- `WEF_{32-hex-guid}_Kanban.Lane` — the swimlane

The `{guid}` is **per team per board**, so the same work item carries a different set of `WEF_*` fields for every team whose board it appears on. Community confirmation of the naming and of reading the lane field name from the board endpoint: [MoveWorkItemsWhenPullRequestCompletes](https://github.com/KevinJCandlert/MoveWorkItemsWhenPullRequestCompletes); Microsoft field docs: [Work item fields](https://github.com/MicrosoftDocs/azure-devops-docs/blob/main/docs/boards/work-items/work-item-fields.md).

### 6.3 Working algorithm

1. `GET .../_apis/work/boards` → pick the board (backlog level).
2. `GET .../_apis/work/boards/{id}` → capture `columns`, `rows`, and the three `fields.*.referenceName` values. Cache keyed by `(project, team, boardId, revision)`.
3. Run the backlog/board query — `GET .../_apis/work/backlogs/{id}/workItems` or a WIQL scoped to the team's area paths and the board's work item types.
4. `POST _apis/wit/workitemsbatch` requesting **exactly** `System.Id, System.Title, System.State, System.WorkItemType, System.AssignedTo, System.Tags` **plus the three `WEF_*` reference names** from step 2.
5. Group by `WEF_*_Kanban.Lane` (swimlane) → `WEF_*_Kanban.Column` (column) → `WEF_*_Kanban.Column.Done` (Doing vs Done half).
6. Enforce/display `itemLimit` per column client-side; the server does not reject WIP-limit violations.

**Moving a card:** PATCH the work item setting the `WEF_*` column/lane fields (and `System.State` if the target column's `stateMappings` implies a different state). Always include `test /rev`. Fall back to a state change if the `WEF_*` write is rejected. Note the Boards UI also supports "move to column/swimlane" from the action menu ([Sprint 210 update](https://learn.microsoft.com/en-us/azure/devops/release-notes/2022/sprint-210-update)), which is what you're mimicking.

### 6.4 Public API sufficiency vs the web UI

**Partly verified / partly unverified.** The public REST surface is sufficient to *reconstruct* a board: columns, split columns, WIP limits, swimlanes, state mappings, card fields (`_apis/work/boards/{id}/cardsettings`, `.../cardrulesettings`), and per-item placement via `WEF_*`. What the public API does **not** give you is the single aggregated payload the web UI uses — the web app calls internal, unversioned `_apis/Contribution/HierarchyQuery` / dataProvider endpoints that return the entire board in one round trip. **(unverified — inferred from network behavior, not documented; do not depend on it.)** Using those internal endpoints would be unsupported, undocumented, and breakable at any sprint boundary — **don't**.

Practical consequence: rebuilding a 300-card board costs you ~1 (boards) + 1 (backlog) + 2 (workitemsbatch @200) ≈ 4 requests. That's acceptable. Cache the schema; refresh cards on pull-to-refresh only.

Also relevant limits: [Work tracking, process, and project limits](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops).

---

## 7. Identity and multi-tenancy

### 7.1 The MSA gap (the headline risk)

Verbatim from [Build Azure DevOps integrations with Microsoft Entra OAuth apps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops) (doc updated 2026-04-02):

> "Microsoft Entra apps don't natively support Microsoft account (MSA) users for the Azure DevOps resource. If you're building an app that must cater to MSA users or support both Microsoft Entra and MSA users, **Azure DevOps OAuth apps remain your best option**. Microsoft is currently working on native support for MSA users through Microsoft Entra OAuth."

And from [No new Azure DevOps OAuth apps beginning April 2025](https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/):

> As of **2025-04-23**, the Azure DevOps OAuth app platform no longer accepts new app registrations; existing apps work until full deprecation **in 2026**.

**These two statements are mutually incompatible for a new app.** The documented path for MSA users is a platform you cannot register on. There is no published resolution as of 2026-09-10 **(unverified whether MSA support has since shipped — the entra-oauth doc as of 2026-04-02 still says "currently working on")**.

**Decision:** ship Entra-only. Treat MSA support as a tracked external dependency. Add a first-run check that classifies the account type and shows an honest message plus the PAT fallback, rather than a cryptic `AADSTS50020`-style error.

### 7.2 Entra app registration specifics

- **Azure DevOps resource ID: `499b84ac-1321-427f-aa17-267ca6975798`**; resource URI `https://app.vssps.visualstudio.com`.
- Add delegated permissions by selecting **Azure DevOps** (not Microsoft Graph) in the API permissions picker; scopes are the familiar `vso.*` set ([available scopes](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops#available-scopes)).
- Use the **`.default` scope** to request a token with everything the app is permissioned for (`499b84ac-1321-427f-aa17-267ca6975798/.default`).
- Register as a **multi-tenant public client** with PKCE and a mobile redirect URI (`msauth.<bundleid>://auth` for MSAL, or a custom scheme / universal link for AppAuth). No client secret on device, ever.
- Many tenants require **admin consent** for a new multi-tenant app. Provide an admin-consent URL and a short doc listing exactly which `vso.*` scopes you request and why. Expect this to be a sales-cycle item, not a technical one.
- Identity ID mismatch: ADO identity ids and Entra object ids differ. Microsoft's guidance is to reconcile via the [ReadIdentities API](https://learn.microsoft.com/en-us/rest/api/azure/devops/ims/identities/read-identities?view=azure-devops-rest-7.1).

### 7.3 Orgs, tenants, and URLs

- **Organization ≠ Entra tenant.** An org is backed by *at most one* tenant (or by MSA). A user with three orgs across two tenants plus a personal org needs **three different tokens**.
- **Org discovery**: `GET https://app.vssps.visualstudio.com/_apis/accounts?memberId={id}&api-version=7.1` ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/account/accounts/list?view=azure-devops-rest-7.1)). One of `ownerId`/`memberId` is required. Get `memberId` from `GET https://app.vssps.visualstudio.com/_apis/profile/profiles/me`. Note this API is **user-context only — service principals are not supported** ([Q&A](https://learn.microsoft.com/en-us/answers/questions/2237442/unable-to-list-azure-devops-organization-by-azure)); irrelevant for a user-delegated app, but it means you can never do org discovery from a backend service identity.
- **Guest (B2B) users** appear in the host tenant's org but authenticate against their home tenant. Token acquisition must target the **resource tenant** (`https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/authorize`), not `/common`, or you'll get the wrong audience. Practical rule: cache tokens keyed by `(tenantId, orgName)` and be prepared to run an interactive flow per tenant.
- **URL forms:** modern `https://dev.azure.com/{org}`; legacy `https://{org}.visualstudio.com`. Org-level REST APIs accept either form regardless of when the org was created ([Work with organization URLs](https://learn.microsoft.com/en-us/azure/devops/extend/develop/work-with-urls?view=azure-devops)). Switching an org to the new domain is **one-way**. Normalize to `dev.azure.com/{org}` internally, but accept pasted `visualstudio.com` URLs in any "add organization" input.
- **Multiple hostnames are unavoidable**: `dev.azure.com` (most APIs), `vssps.dev.azure.com` / `app.vssps.visualstudio.com` (identity, profile, accounts, graph), `vsaex.dev.azure.com` (entitlements), `almsearch.dev.azure.com` (code/work item search), `vstmr.dev.azure.com` (test results), `analytics.dev.azure.com` (OData). Your HTTP layer must route per-service, not assume one base URL. See [Why does ADO use multiple hostnames](https://learn.microsoft.com/en-us/answers/questions/5768945/why-does-azure-devops-rest-apis-use-multiple-hostn).

### 7.4 Avatars and display names

- Graph: `GET https://vssps.dev.azure.com/{org}/_apis/graph/users` / `.../users/{descriptor}` ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/users/list?view=azure-devops-rest-7.1)).
- Avatars: `GET https://vssps.dev.azure.com/{org}/_apis/graph/Subjects/{subjectDescriptor}/avatars?size=&format=` ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/avatars/get?view=azure-devops-rest-7.1)); `IdentityRef._links.avatar` points at `https://dev.azure.com/{org}/_apis/GraphProfile/MemberAvatars/{descriptor}`.
- **Avatar URLs require auth** — same problem as §5.6. Fetch with headers, cache by descriptor, and render initials-with-color as the fallback (which also saves a lot of TSTU on list screens). **Do not** fetch an avatar per row in a virtualized list.

### 7.5 React Native auth reality check

**Microsoft does not ship a supported MSAL SDK for React Native.** The AzureAD org's `msal-react-native-android-poc` is explicitly a proof of concept, Android-only, and "not recommended to be used for React Native applications intended for production" ([package page](https://github.com/AzureAD/microsoft-authentication-library-for-js/packages/292089)). `@azure/msal-react` is for **web React**, not React Native. Community options (`react-native-msal`, `react-native-msal-plugin`) are third-party maintained.

Two viable paths:

| Path | Pros | Cons |
|---|---|---|
| **`react-native-app-auth`** (AppAuth-iOS/Android, listed by Microsoft as a compatible client library) | Standards-based, well maintained, system-browser + PKCE, straightforward Expo config plugin | **No broker** → no device-registration/compliance claims → CA policies requiring a compliant/hybrid-joined device will block you (R3) |
| **Community MSAL wrapper** | Broker support (Authenticator / Company Portal) → device compliance CA can pass; SSO with other Microsoft apps | Unofficial, lags MSAL releases, larger native footprint, more Expo prebuild friction |

Either way: **Expo Go cannot host this.** You need `expo prebuild` + a custom dev client + EAS Build. Budget for it in the project plan; it also affects OTA-update strategy.

---

## 8. Notifications

### 8.1 There is no first-party push for third parties (verified by absence)

Azure DevOps has no public push-notification API, no APNs/FCM relay, and no "register this device for my notifications" endpoint. Delivery channels in the Notification API are `EmailHtml`, service hooks, and (internally) the web notification bell.

### 8.2 The Notification API is configuration, not an inbox

`GET https://dev.azure.com/{org}/_apis/notification/subscriptions?targetId={userGuid}&queryFlags=...&api-version=7.1` ([docs](https://learn.microsoft.com/en-us/rest/api/azure/devops/notification/subscriptions/list?view=azure-devops-rest-7.1)) returns `NotificationSubscription[]` — each is a *rule*: `description`, `subscriber`, `status`, `scope`, `filter` (event type + clause expression, e.g. `eventType: ms.vss-work.workitem-changed-event`, clause `Pushed by = [Me]`), `channel` (`EmailHtml`), `permissions`, and an `_links.edit` pointing at the **web** `_notifications` page. Scope: `vso.notification` (read).

**It returns zero delivered notifications.** There is no `notifications` (plural, delivered) resource, no read/unread state, no history. `_apis/hooks/notifications` exists but is **service-hook delivery diagnostics** (attempts, results) for a subscription you own — not a personal feed.

**Conclusion: the web "Notifications" bell has no public API. (unverified only in the sense that absence is hard to prove — no such endpoint appears in the 7.1/7.2 REST reference.)** The bell is served by internal contribution/dataProvider endpoints; using them would be unsupported.

**What the Notification API *is* good for in your app:**
- Read the user's existing subscriptions and render a "you'll be emailed about X" settings mirror.
- **Create** a subscription on the user's behalf (`POST .../subscriptions`) — e.g. a one-tap "notify me about this PR". Useful, but the delivery is still email.

### 8.3 Service hooks require project-level admin and are per-project

- Creating a subscription requires the **Edit subscriptions** permission in the `ServiceHooks` security namespace; **by default only project administrators have it** (and Project Collection Administrators inherit it). Docs: [Create a service hook subscription programmatically](https://learn.microsoft.com/en-us/azure/devops/service-hooks/create-subscription?view=azure-devops), [View permission](https://learn.microsoft.com/en-us/azure/devops/service-hooks/view-permission?view=azure-devops), [Namespace reference](https://learn.microsoft.com/en-us/azure/devops/organizations/security/namespace-reference?view=azure-devops).
- Subscriptions are **per-project and per-event-type**. A 30-project org means 30 × N subscriptions to manage, each with its own lifecycle and failure state (`SubscriptionStatus` has a rich failure taxonomy: `jailedByNotificationsVolume`, `disabledFromProbation`, `disabledMissingPermissions`, …).
- So a genuine push inbox requires: **your backend** + **org admin authorization** + **per-project subscription provisioning** + **subscription health monitoring**. That's an enterprise feature, not a v1 feature.

### 8.4 Polling-based "my activity": what it can and can't do

**Can do reliably (foreground, ~4 requests):**

| Feed | Call | Notes |
|---|---|---|
| PRs awaiting my review | `GET {org}/_apis/git/pullrequests?searchCriteria.reviewerId={id}&searchCriteria.status=active&$top=50` | Org-wide in one call; add `searchCriteria.repositoryId` to narrow |
| My PRs | same with `searchCriteria.creatorId` | |
| Work items assigned to me / recently changed | one WIQL: `SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.ChangedDate] >= @Today - 14 ORDER BY [System.ChangedDate] DESC` then `workitemsbatch` | Scope to a project when possible; org-wide queries are far more expensive |
| Build/pipeline status | `GET {org}/{project}/_apis/build/builds?minTime={lastSync}&$top=25` | Per project — pin a small set |

**Can't do:**

- **Comment-level granularity without per-PR fan-out.** There's no "all threads changed since T across my PRs" endpoint. You'd have to `GET .../pullRequests/{id}/threads` per PR — cost scales with PR count. Mitigation: only fetch threads for PRs whose `lastMergeSourceCommit`/thread count changed, and only for the top N most recent.
- **@mentions.** No mention feed exists. **(unverified whether any public endpoint surfaces mentions; none found.)** You can approximate by scanning fetched thread content for the user's display name/UPN, which is lossy.
- **True background delivery.** iOS BGAppRefresh gives you no guarantees; Android background work is doze-constrained. Local notifications fired on foreground sync are honest but arrive late.
- **Anything while the app is killed.**

**Recommended product shape:** call it "Activity", refresh on open + pull-to-refresh, fire *local* notifications for newly-observed items since last sync, and be explicit in onboarding and store copy that real-time push requires the (later) admin-authorized backend. Under-promising here avoids the worst review category ("notifications don't work").

---

## 9. Platform, store, and legal

### 9.1 Naming and trademarks

- Microsoft's position ([Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)): without a license, **everything about your app — developer name, app name, logo, description, screenshots, and other collateral — must be unique to you and free of Microsoft's Brand Assets.** The only carve-out is a **truthful statement of compatibility or interoperability within the text description**.
- Practically: `"Foo — for Azure DevOps"` as an **App Store name** is risky; `"Foo"` with a description line "Foo is a mobile client for Azure DevOps® (a Microsoft product). Not affiliated with or endorsed by Microsoft." is the safe pattern.
- Do **not** use the Azure DevOps logo, the infinity mark, or Azure blue-and-logo iconography in your app icon or screenshots.
- Add a clear "not affiliated with Microsoft" disclaimer in the app's About screen, the store listing, and your website footer.
- Windows-store-specific but instructive on Microsoft's expectations: [Trademark and copyright protection](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/trademark-and-copyright-protection).

### 9.2 Apple — Guideline 4.2 Minimum Functionality

[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). A third-party client for someone else's SaaS is exactly the shape reviewers scrutinize. What gets rejected: a URL wrapper, a WebView with a nav bar, an app with no meaningful UI without a connection, an app that just re-skins the web experience.

**Concrete 4.2 hardening for this app:**

- Fully native navigation and gestures; **no WebView on any primary flow** (PR list, diff, work item, board).
- **A real native diff viewer** — syntax highlighting, side-by-side/inline toggle, hunk collapse, tap-to-comment. This alone is a strong 4.2 answer.
- **Offline**: cached PR lists, work items, and previously-viewed diffs readable with no network; queued actions (vote, comment, work item edit) that flush on reconnect.
- Platform integrations reviewers recognize: **share sheet** ingest (paste a PR URL → open it), **Handoff/universal links**, **Home Screen widgets** (PRs awaiting review count), **Siri/App Intents** shortcuts, **biometric app lock**, **Dynamic Type + VoiceOver**.
- **Tablet-specific layouts** — iPad split view / two-pane PR list + diff. Apple explicitly notes iPad-unoptimized layouts; and a phone-stretched layout also invites 4.2.
- Do not gate the entire app behind a login wall with zero explanation — provide a demo/read-only tour so a reviewer without an ADO org can evaluate the app, **and** supply working demo credentials in App Review notes (a scratch ADO org with sample data). Missing reviewer credentials is a top rejection cause for B2B clients.

### 9.3 Google Play

- **Data safety** ([Provide information for Google Play's Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469)) is mandatory for every app; in-scope apps without a declaration are removed. You declare, per 14 data categories, what is collected, what is shared, why, how it's secured, and whether deletion can be requested. A **privacy policy URL is required**.
- Note the definition trap: **"collecting" = any transmission of data off the device**, with a narrow "ephemeral processing" exemption. If v1 is device-only (tokens in Keystore, ADO calls direct from device, crash reporting only), you can declare a very small footprint — say so, and it becomes a marketing asset. **The moment you add the §8.3 notification backend, this declaration changes materially** (you would then receive and store ADO event payloads).
- **Android ID is now explicitly a "Device or other IDs"** declaration ([policy announcement, 2026-04-15](https://support.google.com/googleplay/android-developer/answer/16926792)); developers get at least 30 days from 2026-04-15 to comply. Audit your analytics SDK.
- Verify your crash/analytics SDK's own data collection and declare it — this is the most common source of a false declaration.

### 9.4 Token security on device

- Store refresh tokens **only** in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) / Android Keystore-backed EncryptedSharedPreferences — `expo-secure-store` or `react-native-keychain`. **Never** AsyncStorage/MMKV unencrypted.
- Keep access tokens in memory only where practical; they're short-lived.
- **Never** log tokens, and add a redaction layer to your crash reporter and network logger. Assume any string starting with `eyJ` is a token and scrub it.
- Offer an optional **biometric app lock** and a "sign out everywhere / clear cache" action.
- If you cache PR diffs and work item content on disk, that is customer source code and IP on the device. Encrypt the cache, exclude it from iCloud/Android backup (`NSURLIsExcludedFromBackupKey`, `android:allowBackup="false"` or backup rules), and document retention.
- OTA/CodePush-style updates that change auth code are a supply-chain risk story enterprises will ask about — either don't OTA the auth module or be ready with an answer.

### 9.5 Intune / MDM-managed devices

- Intune **App Protection Policies require the app to integrate the Intune App SDK** or be wrapped with the App Wrapping Tool ([Create and deploy app protection policies](https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy), [MAM FAQ](https://learn.microsoft.com/en-us/intune/app-management/protection/mam-faq)).
- Conditional Access grant **"Require approved client app"** matches only Microsoft's own list — a third-party app is **not** an approved client app and is therefore blocked ([Q&A: Third-party apps and Intune app protection policy](https://learn.microsoft.com/en-us/answers/questions/1468593/third-party-apps-and-intune-app-protection-policy)). The **"Require app protection policy"** grant can in principle be satisfied by an Intune-SDK-integrated app.
- **Is Intune SDK integration realistic for a small third party?** Technically possible (there are RN bridges), but it means native SDK integration on both platforms, a Microsoft onboarding process, and ongoing SDK version churn. **Recommendation: out of scope for v1–v2.** Document it: "Organizations that require Intune app protection policies for Azure DevOps access cannot currently use this app." This *will* cost you some regulated-industry customers — price that in rather than discovering it in a failed pilot.

---

## 10. Azure DevOps Server (on-premises)

**Recommendation: defer. Do not attempt in v1 or v2.**

Reasons, with sources:

- **Version sprawl and API skew.** Supported line today: Azure DevOps Server (2019, 2020, 2022 + updates, and the new **"Azure DevOps Server"** with the *year dropped from the name*, which moved to the **Modern Lifecycle Policy**). See [Azure DevOps Server release notes](https://learn.microsoft.com/en-us/azure/devops/server/release-notes/azuredevopsserver?view=azure-devops) and [Announcing Azure DevOps Server General Availability](https://devblogs.microsoft.com/devops/announcing-azure-devops-server-general-availability/). REST API versions map to Server RTM releases; you would need runtime **API-version negotiation** (probe `_apis/ResourceAreas` or `Options`) and per-feature capability gating. Docs: [REST API versioning](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rest-api-versioning?view=azure-devops).
- **Auth is completely different**: NTLM/Kerberos/Windows auth or on-prem PATs; no Entra, no CA, no MSAL. That's a second auth stack in the app.
- **NTLM is going away anyway**: **NTLM support is being removed from libcurl in September 2026**, which breaks Git-over-HTTPS against on-prem ADO Server for NTLM-reliant customers. Investing in NTLM in 2026 is investing in a dead path.
- **Self-signed / private-CA TLS**: requires custom trust anchors on both platforms (iOS `NSURLSessionDelegate` pinning exceptions or a user-installed profile; Android network security config). Shipping an app that lets users disable certificate validation is a security review failure. A "trust this certificate" UX that is both safe and usable is a genuine multi-week project.
- **Reachability**: on-prem servers are typically behind a corporate VPN; expect support burden that looks like networking triage.

**If you later must:** gate it behind an explicit "Advanced / Server" mode, require a user-imported CA certificate (never blanket-trust), support PAT auth only, negotiate the API version once at connection setup and store a capability matrix, and disable every feature whose endpoint isn't present.

---

## 11. Known breaking changes and deprecations, 2025–2027

| Date | Change | Impact on this app |
|---|---|---|
| **2025-04-23** | **No new Azure DevOps OAuth app registrations.** [Blog](https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/) | Legacy OAuth is not an option. Forces Entra-only → forces the MSA gap (R1). |
| **2025-09** | **ARM audience removed from ADO sign-in/token refresh.** [Blog](https://devblogs.microsoft.com/devops/removing-azure-resource-manager-reliance-on-azure-devops-sign-ins/) | Admins' old ARM-scoped CA policies no longer cover ADO; expect tenants to add new ADO-scoped CA policies (which then hit your app). |
| **2025-07-07** | **Markdown for work item large text fields GA.** [Blog](https://devblogs.microsoft.com/devops/markdown-support-arrives-for-work-items/) | Mixed HTML/Markdown corpus forever; irreversible per-field conversion (R9). |
| **2026** (exact date **unpublished / unverified**) | **Azure DevOps OAuth platform end of life.** Apps with secrets expired >180 days are already being removed. | Any dependency on legacy OAuth dies. Also removes the documented MSA workaround entirely. |
| **2026-03-15 → superseded** | Blocking of new/regenerated **global PATs** was announced then **called off**; creation continues until Dec 1. [Blog](https://devblogs.microsoft.com/devops/retirement-of-global-personal-access-tokens-in-azure-devops/) | If you support PAT fallback, warn users off global PATs now. |
| **2026-12-01** | **All existing global PATs fully decommissioned — they stop working.** (No change for Azure DevOps **Server**.) | PAT fallback must be org-scoped only. Detect global PATs and warn. |
| **2026-09** | **NTLM removed from libcurl** → Git-over-HTTPS to on-prem ADO Server breaks for NTLM users. | Reinforces "defer on-prem" (R18). |
| **2026-07-01** | Azure DevOps **workload-identity-federation issuer** (`https://vstoken.dev.azure.com`) deprecated. [Blog](https://devblogs.microsoft.com/devops/retirement-of-azure-devops-issuer-in-workload-identity-federation-service-connections/) | Not directly relevant (pipelines/service connections), but a signal of the auth-modernization cadence. |
| **2027** | **Public projects convert to private; anonymous access permanently disabled; public visibility option removed.** [Public projects retirement](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/public-projects-retirement?view=azure-devops) | Remove/never build unauthenticated browsing. Existing forks keep working for authenticated users only. |
| **2027-07-01** | ADO WIF issuer end of life. | As above. |
| Ongoing | **Preview API deactivation**: once version *N* GAs, `N-preview` is deprecated and **can be deactivated after 12 weeks**; requests specifying a deactivated `-preview` version are **rejected**. [REST API versioning](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rest-api-versioning?view=azure-devops) | Never ship a `-preview` endpoint in a released build (this affects `wit/tags`, some process APIs, search). Centralize the api-version constant and feature-flag preview usage. |
| Already done | **Alternate Credentials unsupported.** [Blog](https://devblogs.microsoft.com/devops/azure-devops-will-no-longer-support-alternate-credentials-authentication/) | Don't implement basic-auth-with-alt-creds. |
| N/A | **`{org}.visualstudio.com` legacy domain**: deprecated long ago in favor of `dev.azure.com/{org}`; org-level REST APIs still accept **either** form. Switching an org to the new domain is one-way. **No published hard retirement date for the legacy hostname (unverified).** | Accept both on input, normalize to `dev.azure.com`. Don't hardcode either. |

Watch these feeds monthly: [Azure DevOps release notes](https://learn.microsoft.com/en-us/azure/devops/release-notes/features-timeline-released), [Azure DevOps Roadmap](https://learn.microsoft.com/en-us/azure/devops/release-notes/features-timeline), [Azure DevOps Blog](https://devblogs.microsoft.com/devops/).

---

## 12. Consolidated recommendations

**Architecture**

1. **Entra OAuth only, multi-tenant public client, PKCE, system browser.** Accept the MSA gap explicitly. Provide a PAT fallback that is clearly secondary.
2. **Per-(tenant, org) token cache.** Multi-hostname-aware HTTP layer (`dev.azure.com`, `vssps.dev.azure.com`, `almsearch.dev.azure.com`, …).
3. **Pin `api-version=7.1`.** One constant. No preview endpoints in shipped builds.
4. **A TSTU budget as a first-class runtime object** — track `X-RateLimit-Cost`, react to `Retry-After`/`X-RateLimit-Delay`, and expose a "sync paused" state rather than failing silently.
5. **Cache tiers**: immutable (blobs by `objectId`, avatars by descriptor, attachments by GUID) → forever; schema (work item types, board config, process config) → 24 h; live lists → 60 s.
6. **CAE claims-challenge handling** wired into the HTTP client from day one.

**Feature sequencing**

- **v1**: PR review (list → files → native diff → line comments → vote → set auto-complete), work items (view, comment, state change, assign), builds status, foreground Activity feed with local notifications.
- **v1.5**: Boards (read + drag to column/lane), work item create with dynamic forms, search.
- **v2**: Optional admin-authorized backend for real push via service hooks; suggestions composer (after verifying §4.5); on-prem only if a paying customer funds it.

**Things to verify empirically before writing code** (each is marked unverified above):

1. How to **detect** `multilineFieldsFormat` (HTML vs Markdown) on a work item read.
2. The **wire format of a PR suggestion** comment (likely a ` ```suggestion ` fence).
3. Whether the **identity picker** endpoint (`_apis/IdentityPicker/Identities`) is usable/stable, or whether Graph user search suffices.
4. Real **TSTU costs** of your planned poll cycle, measured via `X-RateLimit-Cost` against a representative org.
5. Whether **MSA support in Entra OAuth for the ADO resource** has shipped (re-check the entra-oauth doc each quarter).

---

## Sources

- [Change application connection and security policies for organizations](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/change-application-access-policies?view=azure-devops)
- [Conditional Access policies on Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops)
- [Manage personal access tokens using policies](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/manage-pats-with-policies-for-administrators?view=azure-devops)
- [Build Azure DevOps integrations with Microsoft Entra OAuth apps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops)
- [OAuth 2.0 authentication for Azure DevOps REST APIs (scopes)](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops)
- [No new Azure DevOps OAuth apps beginning April 2025](https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/)
- [Retirement of Global Personal Access Tokens in Azure DevOps](https://devblogs.microsoft.com/devops/retirement-of-global-personal-access-tokens-in-azure-devops/)
- [Removing Azure Resource Manager reliance on Azure DevOps sign-ins](https://devblogs.microsoft.com/devops/removing-azure-resource-manager-reliance-on-azure-devops-sign-ins/)
- [Rate and usage limits](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops)
- [Integration best practices](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/integration-bestpractices?view=azure-devops)
- [Work tracking, process, and project limits](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/object-limits?view=azure-devops)
- [Monitor usage of Azure DevOps Services](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/usage-monitoring?view=azure-devops)
- [Pull Request Iteration Changes – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get?view=azure-devops-rest-7.1)
- [Diffs – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/diffs/get?view=azure-devops-rest-7.1)
- [Pull Request Threads – Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/create?view=azure-devops-rest-7.1)
- [Pull Request Reviewers – Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-reviewers/create-pull-request-reviewer?view=azure-devops-rest-7.1)
- [Review and comment on pull requests](https://learn.microsoft.com/en-us/azure/devops/repos/git/review-pull-requests?view=azure-devops)
- [Complete, abandon, or revert pull requests](https://learn.microsoft.com/en-us/azure/devops/repos/git/complete-pull-requests?view=azure-devops)
- [Merge strategies and squash merge](https://learn.microsoft.com/en-us/azure/devops/repos/git/merging-with-squash?view=azure-devops)
- [Set and manage branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops)
- [GitPullRequestCompletionOptions](https://learn.microsoft.com/en-us/javascript/api/azure-devops-extension-api/gitpullrequestcompletionoptions)
- [Work Items – Update](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/update?view=azure-devops-rest-7.1)
- [Work Item Types Field – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/work-item-types-field/get?view=azure-devops-rest-7.1)
- [Default rule reference](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/rule-reference?view=azure-devops)
- [Attachments – Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/attachments/create?view=azure-devops-rest-7.1)
- [Markdown Support Arrives for Work Items](https://devblogs.microsoft.com/devops/markdown-support-arrives-for-work-items/)
- [Markdown for large text fields (private preview)](https://devblogs.microsoft.com/devops/markdown-for-large-text-fields-private-preview/)
- [Boards – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/work/boards/get?view=azure-devops-rest-7.1)
- [Manage columns on your board](https://learn.microsoft.com/en-us/azure/devops/boards/boards/add-columns?view=azure-devops)
- [Work item fields (WEF_ / Kanban fields)](https://github.com/MicrosoftDocs/azure-devops-docs/blob/main/docs/boards/work-items/work-item-fields.md)
- [Notification Subscriptions – List](https://learn.microsoft.com/en-us/rest/api/azure/devops/notification/subscriptions/list?view=azure-devops-rest-7.1)
- [Manage personal notification settings](https://learn.microsoft.com/en-us/azure/devops/organizations/notifications/manage-your-personal-notifications?view=azure-devops)
- [Integrate with service hooks](https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview?view=azure-devops)
- [Create a service hook subscription programmatically](https://learn.microsoft.com/en-us/azure/devops/service-hooks/create-subscription?view=azure-devops)
- [Service hooks view permission](https://learn.microsoft.com/en-us/azure/devops/service-hooks/view-permission?view=azure-devops)
- [Security namespace reference](https://learn.microsoft.com/en-us/azure/devops/organizations/security/namespace-reference?view=azure-devops)
- [Accounts – List](https://learn.microsoft.com/en-us/rest/api/azure/devops/account/accounts/list?view=azure-devops-rest-7.1)
- [Graph Users – List](https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/users/list?view=azure-devops-rest-7.1)
- [Graph Avatars – Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/avatars/get?view=azure-devops-rest-7.1)
- [Identities – Read Identities](https://learn.microsoft.com/en-us/rest/api/azure/devops/ims/identities/read-identities?view=azure-devops-rest-7.1)
- [Work with organization URLs in Azure DevOps extensions](https://learn.microsoft.com/en-us/azure/devops/extend/develop/work-with-urls?view=azure-devops)
- [REST API versioning for Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rest-api-versioning?view=azure-devops)
- [Public projects retirement in Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/public-projects-retirement?view=azure-devops)
- [Azure DevOps Server release notes](https://learn.microsoft.com/en-us/azure/devops/server/release-notes/azuredevopsserver?view=azure-devops)
- [Announcing Azure DevOps Server General Availability](https://devblogs.microsoft.com/devops/announcing-azure-devops-server-general-availability/)
- [Retirement of Azure DevOps issuer in workload identity federation service connections](https://devblogs.microsoft.com/devops/retirement-of-azure-devops-issuer-in-workload-identity-federation-service-connections/)
- [Claims challenges, claims requests, and client capabilities (CAE)](https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge)
- [Microsoft Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Google Play Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play policy announcement, April 15, 2026](https://support.google.com/googleplay/android-developer/answer/16926792)
- [Intune: create and deploy app protection policies](https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy)
- [Intune MAM FAQ](https://learn.microsoft.com/en-us/intune/app-management/protection/mam-faq)
- [Third-party apps and Intune app protection policy (Q&A)](https://learn.microsoft.com/en-us/answers/questions/1468593/third-party-apps-and-intune-app-protection-policy)
- [MSAL for React Native (proof of concept, Android-only)](https://github.com/AzureAD/microsoft-authentication-library-for-js/packages/292089)
- [pr-agent issue: Incorrect inline code suggestion formatting in Azure DevOps](https://github.com/qodo-ai/pr-agent/issues/2110)
