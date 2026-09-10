# Azure DevOps Mobile App — Discovery Summary and Proof of Viability

**Date:** 2026-09-10
**Target:** iOS + Android, phone + tablet, React Native / Expo. A client for Azure DevOps Services that blends the Jira mobile app (boards, work items) and the GitHub mobile app (repos, PR review) experiences.
**Method:** five parallel research passes against Microsoft Learn, Expo docs, app stores and community sources (documents 01–05 in this folder), reconciled against each other and against live, unauthenticated probes of public Azure DevOps projects (`verification/`).

---

## 0. Decisions taken after review (2026-09-10)

Kelly reviewed the findings and settled three scope questions. These override the corresponding recommendations further down and in documents 01–05.

| Decision | Effect on the plan |
|---|---|
| **Launch with Entra OAuth only.** PAT login for personal Microsoft accounts moves to the roadmap. | v1 sign-in is one button: Entra ID authorization code + PKCE, `organizations` authority. MSA users get an honest "not supported yet" screen. PAT login stays designed for (per-org token model) but is not built. |
| **Notifications via a Marketplace extension plus a relay in the customer's Azure tenancy.** | Replaces the "hybrid polling then optional backend" recommendation. Polling remains the zero-setup fallback. Design in [06-notification-relay-and-extension.md](06-notification-relay-and-extension.md). |
| **Cloud only.** Azure DevOps Services. Azure DevOps Server is out of scope. | No NTLM, no custom certificates, no API version negotiation. The HTTP layer still takes a configurable base URL because it costs nothing. |
| **v1 writes: read plus lightweight writes.** Comment, vote, change state and assignee, move cards, set auto-complete. Full field editing and work item creation in v1.1. | Smaller first consent screen. Incremental consent for write scopes. |
| **Tablets at launch: responsive phone layout that scales.** True master-detail panes in v2. | `supportsTablet` on, breakpoint-driven layouts, no custom split-view component in v1. |
| **Business model: the app is fully free on both stores. Anything purchasable is sold through the Azure DevOps Marketplace extension.** | Avoids App Store and Play billing entirely. The extension and relay (document 06) are the paid product. Marketplace supports paid extensions billed through the customer's Azure subscription; confirm current publisher requirements. |
| **Platforms: iOS and Android together**, TestFlight and Play internal testing before public listing. | One Expo codebase, EAS Build and Submit for both. |
| **Rich text: full rich-text editor in v1** for work item descriptions. | TenTap editor writing HTML, plus a Markdown editing path. Non-negotiable safeguards: detect the field format before editing (`multilineFieldsFormat`, returned at 7.1 when the read has no `fields` filter; see section 6a), never convert between HTML and Markdown, dry-run with `validateOnly=true`, and use the `test /rev` op so a stale edit fails instead of overwriting. |
| **Enterprise broker support in v1.** Build a native Expo Module over MSAL iOS and MSAL Android. | Unblocks tenants with device-compliance Conditional Access from day one. Adds a config plugin, `msauth.{bundleId}://auth` redirect URIs, and a token cache owned by MSAL rather than by `expo-auth-session`. This replaces the earlier v1 `expo-auth-session` recommendation. |
| **Brand name: Boardhop** (locked 2026-09-10, from [07-naming-candidates.md](07-naming-candidates.md)). | Use for the store listing, Entra app display name, publisher verification, and domain registration. Verify domain and store-name availability at a registrar before public listing. Compatibility statement "works with Azure DevOps" goes in the description only. |
| **Build order: work items and boards first**, then pull request review, then pipelines and the activity feed. | First spikes are dynamic forms, `multilineFieldsFormat`, the Kanban column patch, and board card settings. The diff engine comes second. |
| **Offline: read cache plus queued writes.** Comments, votes, state changes and card moves queue and flush on reconnect. | Every queued write carries the `rev` it was made against; a rejected `test /rev` surfaces a conflict screen rather than silently overwriting. |
| **Push gateway: self-hosted at kammcs.** The tenant relay sends opaque pointers to a small kammcs service that holds the APNs and FCM credentials. | Strongest data-stays-in-tenant story. One small service to operate. |
| **Publisher accounts: need to set up** Partner Center (MPN ID for Entra publisher verification) and a Visual Studio Marketplace publisher. | Added to the pre-launch checklist below. Start early; verification lead time is measured in weeks. |
| **Telemetry: crash reports only, scrubbed.** No usage analytics. | Redact tokens, org names, titles, paths and code from crash payloads. Declare only crash diagnostics in store privacy forms. |
| **Source code on GitHub.** Testing and validation against Azure DevOps. | Dogfooding needs a real Azure DevOps org; see next row. |
| **Test org: `https://dev.azure.com/puremedia/`**, an Entra-backed org belonging to a company Kelly works with. | All spikes must be non-destructive: use a dedicated scratch project inside the org (or a separate scratch org) for work item creation, Markdown conversion, PR line comments and webhook tests. Still need a guest account from a second tenant for the cross-tenant spike. |

### Stack re-evaluation (2026-09-10, pending Kelly's decision)

Before scaffolding, Kelly asked whether Expo is the easiest path or whether Microsoft's own stack or Flutter is better suited. Three evaluations ([08a MAUI](08a-dotnet-maui-evaluation.md), [08b Flutter](08b-flutter-evaluation.md), [08c React Native and others](08c-react-native-and-other-stacks.md)) are compared in [08-stack-comparison.md](08-stack-comparison.md). **Recommendation: Flutter.** A maintained broker-capable MSAL wrapper (`msal_auth`) exists, kammcs has shipped two Flutter apps with most of Boardhop's building blocks, and the v1 native MSAL module for React Native disappears. Costs: no first-party over-the-air updates, iOS text-input fidelity, HTML editing through Delta conversion or a WebView. .NET MAUI only wins if a named prospect requires Intune App Protection Policies. Every decision above except the Expo-specific implementation notes survives the switch; the "native Expo Module over MSAL" row becomes "adopt `msal_auth`, add a claims-challenge hook".

### Pre-launch checklist (administrative items with lead time)

1. Enroll kammcs in Microsoft Partner Center and obtain a verified MPN ID.
2. Register the Entra application (multi-tenant, public client, mobile platform, `msauth.{bundleId}://auth` redirect URIs, delegated `vso.*` permissions) and complete publisher verification.
3. Create a Visual Studio Marketplace publisher and confirm the current requirements for paid extensions billed through Azure.
4. Apple Developer Program and Google Play Console accounts for kammcs, with the chosen brand name.
5. Privacy policy URL, App Store privacy labels, Google Play data-safety form (reflecting that the app sends no content to kammcs; the gateway sees only opaque pointers).
6. A scratch Azure DevOps org with sample data and reviewer credentials for App Store review.
7. Domain and store-name reservation once the brand is chosen.

A note on "standard MSAL login flow": Microsoft ships no supported MSAL for React Native, and the community wrapper is unmaintained. Kelly chose to build a native Expo Module over MSAL iOS and Android for v1 so that the Authenticator broker and device-compliance Conditional Access work from launch. The Entra PKCE flow is the same either way; the module owns token acquisition, silent refresh, and the token cache.

---

## 1. Verdict

**Viable. Build it.** The public REST API covers every core screen, Expo can host it, and no competitor has shipped the combination of a Jira-quality board and a GitHub-quality PR review for Azure DevOps. Microsoft has never shipped a native app and has announced none.

Three things make it harder than a GitHub client would be, and each has a workable answer:

| Hard problem | Why | Answer |
|---|---|---|
| **Personal Microsoft accounts cannot use OAuth** | Microsoft Entra OAuth still does not support MSA users for the Azure DevOps resource (doc revised 2026-05-08). The legacy Azure DevOps OAuth platform that did support them closed to new registrations on 2025-04-23 and retires in 2026. | Entra OAuth as the primary login, plus a per-organization Personal Access Token (PAT) login shipped in v1 as a visible, co-equal option. This is what SmartGit told its users in May 2026. Re-check quarterly for MSA support. |
| **No notification inbox and no push relay** | The Notification API only manages email subscriptions. Service hooks need a project administrator, per project. There is no APNs/FCM relay. | v1: a foreground "Activity" feed built from a handful of cheap polls, with local notifications for new items. v2: a small webhook backend that an org admin opts into for real push. |
| **No unified diff endpoint** | Every diff-shaped API returns change metadata and blob SHAs, never hunks. Verified live in `verification/probe-results.txt` sections 6–8. | Fetch base and target blobs, diff on device with a Myers implementation, render with a virtualized list. Blobs are content-addressed, so cache them forever by SHA. |

The one decision that must be right on day one is the token model: **per tenant, per organization, chunked in the secure store**. Everything else can evolve.

---

## 2. What the research established

### 2.1 API coverage (document 01)

The 7.1 GA API covers: organizations and profile, projects and teams, work items (read, batch, JSON Patch create/update, WIQL, saved queries, attachments, relations, types/fields/states), boards (columns, rows, WIP limits, split columns, swimlanes, card placement via team fields), backlogs and sprints, repos, branches, commits, file content, pull requests (list, get, create, update, complete, abandon, auto-complete, reviewers, votes, threads, line comments, iterations, changed files, labels, statuses, linked work items), pipelines (list, runs, timeline, logs, queue, cancel, retry stage, YAML approvals, classic releases), wiki, work item search and code search, Graph identity and avatars.

Real gaps, all with workarounds:

- No PR diff hunks (client-side diff).
- No notification inbox, read state, or push (see above).
- No org-wide PR list in the documentation. The pitfalls document assumed one exists. The live probe could not settle it anonymously (section 15). Treat as **fan out per project until an authenticated test proves otherwise**.
- No follow/unfollow API and no org-wide mentions feed.
- No suggested-reviewers endpoint.
- No live log streaming (poll the timeline while foregrounded).
- Work item Comments API has never left preview (`7.1-preview.4`). Pin the exact revision.
- Board card field and style settings are untyped objects with no schema. Reverse-engineer from a live response.

### 2.2 Authentication and organization selection (document 02)

- **Entra ID OAuth 2.0, authorization code + PKCE, multi-tenant public client.** Resource ID `499b84ac-1321-427f-aa17-267ca6975798`. Granular delegated `vso.*` scopes work (since September 2023). Request narrow read scopes first and add write scopes by incremental consent.
- **The Azure DevOps org policy "Third-party application access via OAuth"**, which defaults off on new orgs, does **not** apply to Entra tokens. This would otherwise have been fatal.
- **Org discovery:** profile call, then accounts call, both on `app.vssps.visualstudio.com`. Verified live that an unauthenticated call there advertises both `Bearer` and `Basic` challenges and redirects to an `entra.web.2` sign-in (section 1).
- **Multi-tenant reality:** an org backed by tenant A only accepts a token from tenant A. Cache tokens keyed by tenant and re-authorize silently per tenant when a probe returns 401.
- **Global PATs stop working on 2026-12-01.** PAT login must be per organization, with the user supplying the org name or URL. Never build "one PAT lists all orgs".
- **Broker / Conditional Access "compliant device" tenants are out of scope for v1.** A system-browser flow cannot satisfy them. The community `react-native-msal` package has had no release since December 2021. Budget a small custom Expo Module over MSAL native for v2 if an enterprise customer needs it.
- **`expo-secure-store` has a historical 2 KB per-item limit on iOS** and Entra tokens exceed it. A chunking wrapper is required on day one.
- **Publisher verification** in Entra must be completed before store launch or tenants using the recommended consent policy will block the app.

### 2.3 Expo tech stack (document 03)

Expo SDK 57 (React Native 0.86, New Architecture only). A development build is required from the start; Expo Go cannot run the OAuth flow. Recommended core: Expo Router, TanStack Query with an MMKV-backed persister, `expo-secure-store`, FlashList v2 for diffs and boards, the `diff` package for Myers diffs, a Prism-based per-line highlighter, `@native-html/render` (the maintained successor of `react-native-render-html`), a maintained Markdown renderer fork, TenTap for rich text editing, `expo-image` with headers for authenticated attachment images.

Two ecosystem gaps need custom engineering: **tablet master-detail layout** (Expo Router's split view is alpha and iOS-only) and **cross-column Kanban drag-and-drop** (no turnkey library). Size both as multi-week components.

### 2.4 Competition and demand (document 04)

- No official Microsoft app. The only first-party mobile surface is a mobile-web view of a single work item, unchanged since 2019.
- The most complete third-party app (Az DevOps, Flutter, open source) has roughly ten thousand Android installs and 4.4 stars on iOS. Everything else is thinner or brand new. Nearly all are PAT-first, and reviewers complain about the Microsoft login failing.
- GitHub Mobile and Jira Cloud set the bar: triage inbox, inline PR review and merge, swipe-to-move boards, JQL filters, iPad layouts, widgets, dark mode.
- Demand is real but diffuse. Monetization in this niche is free or small in-app purchases, so plan freemium.

### 2.5 Pitfalls and policies (document 05)

- Rate limits: 200 TSTU per user per sliding five minutes. **Throttling arrives as a slow HTTP 200 with a `Retry-After` header, not a 429.** Verified that `X-RateLimit-Cost` is returned on ordinary responses (section 11). The HTTP layer must read rate headers on successful responses.
- Work item schemas vary per process and per project. Build forms from type and field metadata. Use `validateOnly=true` for dry runs and the `test /rev` JSON Patch op for concurrency.
- Markdown in work item text fields (GA July 2025) is opt-in per field and **irreversible**. Never round-trip a field the user did not author.
- Azure DevOps **does** support suggested changes in PR comments (correcting an assumption in the brief). The wire format is unverified; test on a scratch PR before designing a composer.
- Board card placement lives in per-team `WEF_{guid}_Kanban.*` fields. Read the reference names from the board object, never synthesize them, and send the column field and `System.State` in one patch.
- Naming: the app name and icon must not use "Azure DevOps" or Microsoft marks. A compatibility statement belongs in the description.
- Defer on-premises Azure DevOps Server. It has no OAuth, needs NTLM or PATs, and NTLM leaves libcurl in September 2026.

---

## 3. Contradictions between the five documents, and how they were resolved

| Topic | Documents disagreed | Resolution |
|---|---|---|
| PAT login: primary, co-equal, or buried fallback | 01 calls PATs a non-starter for consumers; 02 says co-equal in v1; 04 and 05 say secondary | **Co-equal but Entra-first.** Entra is the default button. PAT is the second visible button because MSA users have no other path. Per-org only. |
| Org-wide PR list endpoint | 05 uses `{org}/_apis/git/pullrequests`; 01 says project is required and no org-level endpoint is documented | Undocumented. Anonymous probe returns 302, so inconclusive. **Design for per-project fan-out**, then test authenticated and simplify if it works. |
| Which MSAL wrapper to use | 03 lists `react-native-msal` as viable; 02 shows it unmaintained since 2021; 05 suggests `react-native-app-auth` | **`expo-auth-session` for v1.** No broker support either way. Custom Expo Module over MSAL native only when an enterprise customer requires device-compliance Conditional Access. |
| Push backend mandatory in v1 | 03 says mandatory; 01 and 05 say hybrid | **Hybrid.** Polling and local notifications in v1. Backend plus admin-enabled service hooks in v2. Store copy must say notifications are best-effort until then. |
| Suggested changes in PR comments | 04 says unverified; 05 says the feature exists | Exists in the web UI. Wire format unverified. Spike it. |
| Detecting HTML vs Markdown on a work item | 05 says unverified; 01 says `multilineFieldsFormat` appears only in the 7.2-preview schema | Live probe (section 14) shows `wit/workitems` is routable at **`7.2-preview.2` and `7.2-preview.3`**, not `7.2-preview.1` as document 01 states. Pin `7.2-preview.3` on the work item read path and confirm the property appears with an authenticated read. |
| App naming pattern | 03 says "Brand for Azure DevOps" is accepted practice; 05 says even that is risky | Use a distinct brand name. Put "works with Azure DevOps" in the description only. |

---

## 4. Live verification (what was actually proven, not just read)

Script: `verification/probe-public-api.sh`. Output: `verification/probe-results.txt`. All calls were unauthenticated against Microsoft's public `dnceng-public` and `dnceng` projects, so they will stop working when public projects are retired in 2027.

| # | Proven |
|---|---|
| 1 | Unauthenticated profile call redirects to an Entra sign-in and advertises `Bearer` and `Basic` challenges. |
| 2–4 | Repos, work item types with custom states (24 types in an inherited process), and the PR list all return on plain 7.1. |
| 5 | PR detail carries merge commits, completion options (squash, delete source branch, auto-complete), reviewer votes, and avatar links. |
| 6 | Iteration changes return path, change type and blob object IDs only. The iterations list itself requires authentication even on a public project. |
| 7 | `diffs/commits` returns change counts and a file list, no line content. |
| 8 | File content at a specific commit is fetchable through the Items API for client-side diffing. |
| 9 | PR threads mix system events and text comments, with HTML in comment bodies and null thread context for non-file comments. |
| 10 | Build list, a 2,253-record timeline, and raw log lines all return on 7.1. |
| 11 | `X-RateLimit-Cost` is present on ordinary 200 responses. |
| 12 | `connectionData` returns identity and deployment type in one call. |
| 13 | `ResourceAreas` enumerates 28 distinct service hosts for one org. The HTTP layer must route per service, not per base URL. |
| 14 | `wit/workitems` routes at 7.1, 7.2-preview.2 and 7.2-preview.3. |
| 15 | Org-level PR list needs an authenticated test. |

---

## 5. Recommended architecture

```
Sign-in ──► Entra OAuth (expo-auth-session, PKCE, /organizations authority)
        └─► PAT per org (user pastes token + org URL)
                    │
        Token store: expo-secure-store, chunked, keyed by (tenantId | org)
                    │
        Org discovery: profiles/me → accounts?memberId → org picker
        (PAT path: org supplied by user; discovery best-effort only)
                    │
        HTTP layer: per-service host routing (ResourceAreas), api-version pinned per
        operation, credential strategy per org, rate-limit headers read on 200s,
        single-flight refresh with rolling refresh tokens, CAE claims-challenge hook
                    │
        Data: TanStack Query + MMKV persister. Cache tiers:
          forever  → blobs by SHA, attachments by GUID, avatars by descriptor
          24 h     → work item types/fields, board config, backlog config, repo lists
          60 s     → PR lists, threads, build status
                    │
        Screens: Activity · Work items · Boards · Pull requests · Pipelines · Settings
        Responsive layout: breakpoint-driven master-detail, not device checks
```

**Scopes for v1 (read-mostly):** `vso.profile`, `vso.project`, `vso.work`, `vso.code`, `vso.build`, `offline_access`. Add `vso.threads_full` and `vso.work_write` for commenting and editing, `vso.code_write` for votes and completion, `vso.build_execute` for queue and cancel, each by incremental consent when the feature ships.

---

## 6. Phasing

**v1 (prove the thesis)**
- Entra sign-in only; multi-org switcher; biometric lock option. (PAT sign-in deferred, see section 0.)
- Work items: my work, saved queries, view, edit fields via dynamic forms, comment, attach, create.
- Pull requests: list per project, overview with policy status, changed files, native unified diff, line comments, vote, set auto-complete, complete where policy allows.
- Boards: Kanban read with swimlanes and WIP limits, move card between columns, sprint taskboard move. Backlog reorder.
- Pipelines: runs, stage/job tree, logs, cancel, queue.
- Activity feed: foreground polling, local notifications for new items.
- Dark mode. Phone-first responsive layout that is acceptable on tablets.

**v2 (differentiate)**
- Real push via the Marketplace extension and tenant-hosted relay (document 06), with triage actions.
- PAT sign-in per organization for personal Microsoft accounts, unless Microsoft ships MSA support for Entra OAuth first.
- True tablet multi-pane layouts.
- Drag-and-drop board gestures, swipe-to-move backlog.
- Suggested-change composer (after the wire-format spike).
- WIQL-backed custom filters, widgets.
- MSAL native module for broker-dependent tenants, if demanded.

**Out of scope**
- Azure DevOps Server on-premises (decided 2026-09-10).
- Intune App Protection Policy support.
- Test Plans, Artifacts.

---

## 6a. Spike results (2026-09-10, puremedia org)

Eight read-only spikes ran against the puremedia org. Full evidence in [spikes/results/README.md](spikes/results/README.md). Three findings correct the research documents:

- **An org-level PR list exists and filters by reviewer.** The inbox is one call. Documents 01 and 05 disagreed; 05 was right in practice, though the endpoint is undocumented, so keep per-project fan-out as the fallback.
- **The HTML-versus-Markdown flag is available at plain 7.1.** `multilineFieldsFormat` is populated on any work item read that does not pass a `fields` filter. No 7.2-preview dependency, and `workitemsbatch` at 7.2-preview.3 returns 400 anyway. Documents 01 and 05 were both wrong. The rich-text editor decision in section 0 should read "fetch the item without a `fields` filter" instead of "pin 7.2-preview.3".
- **WEF field names cannot be derived from the board id.** Always read them from `board.fields`.

Also confirmed: `validateOnly=true` returns field-level rule errors and a stale `test /rev` returns HTTP 412, which is exactly what the dynamic forms and the offline write queue need. One poll cycle costs about 0.013 TSTU. Field metadata for one type costs about 1.1 TSTU, so it must be cached. Card settings and rule settings schemas are captured.

Write spikes in the scratch project "DevOps Mobile App" then settled the two Boards-first unknowns:

- **Moving a card needs only the WEF column field.** Writing the column alone derives `System.State` and `System.Reason`; writing State alone derives the column. `System.BoardColumn` is read-only. Sending column and state together stays the safe default. An invalid column name surfaces as a rule error on State, so validate against `board.columns` first. The Done flag is accepted silently on non-split columns, so only send it for split columns.
- **Markdown descriptions round-trip cleanly**, and, unlike the web UI, the REST API allowed converting a Markdown field back to HTML. The format map is populated from the first save. The preview Comments API stores Markdown and returns server-rendered HTML, so the app renders comments from `renderedText`.

The PR spike then ran after the PAT was broadened:

- **Line comments track across pushes, but only when read for the right iteration.** A thread posted on line 6 with `changeTrackingId` and iteration context still reads as line 6 by default after three lines were inserted above it. Reading threads with `$iteration=N&$baseIteration=0` returns the tracked line (9) plus the original position in `trackingCriteria`. The diff viewer must always read threads for the iteration pair it is displaying.
- The PR author can vote, labels work, and a whole PR can be seeded through REST, which is how the test harness will work.
- **Suggested changes use the GitHub-style ```` ```suggestion ```` fence in the comment body.** Kelly confirmed the comment posted on PR 8319 rendered as an applyable suggestion in the web UI. No special API field is involved; the composer emits the fence and anchors the thread to a right-hand line.
- With a broad-scope PAT the `app.vssps.visualstudio.com` profile and accounts APIs still return 401, which supports Microsoft's statement that they accept only Entra tokens. The roadmap PAT login stays per-org.

## 7. Spikes to run before writing product code

Each is cheap and removes a documented unknown. They need one Entra-backed org, one MSA-backed org, and ideally one guest account in a second tenant.

1. **Token sizes.** Measure real Entra access and refresh token bytes for an enterprise user with many group claims. Confirms the chunking design.
2. ~~**PAT against profile and accounts APIs.**~~ Settled: Entra-only on `app.vssps`; the org-scoped profile endpoint works with a PAT (section 6a).
3. **Cross-tenant 401 hint.** Check whether a 401 from an org in another tenant carries `WWW-Authenticate: Bearer authorization_uri=...{tenantId}`.
4. ~~**Org-level PR list.**~~ Settled: works (section 6a).
5. ~~**`multilineFieldsFormat` on read**~~ Settled: returned at 7.1 without a `fields` filter (section 6a).
6. ~~**Suggestion wire format.**~~ Settled 2026-09-10: a ```suggestion fence in the comment body (section 6a).
7. ~~**Kanban column patch.**~~ Settled: it does (section 6a).
8. ~~**Line comment anchoring.**~~ Settled: tracks across pushes when read with `$iteration`/`$baseIteration` (section 6a).
9. ~~**TSTU cost of the planned Activity poll cycle**~~ Settled: about 0.013 TSTU per cycle (section 6a).
10. ~~**Board card settings schema.**~~ Settled: captured in spike 10 results.
11. **Publisher verification lead time** for the Entra app registration.

---

## 8. Document index

| File | Contents |
|---|---|
| [01-api-coverage.md](01-api-coverage.md) | ~90-row endpoint coverage table, per-area endpoint details, gaps, scopes, versioning, rate limits, on-prem parity |
| [02-authentication.md](02-authentication.md) | Entra OAuth for mobile, MSA gap, PAT lifecycle and policies, org and tenant discovery, Expo auth libraries, secure storage, broker decision, login flow sequence |
| [03-expo-tech-stack.md](03-expo-tech-stack.md) | Expo SDK 57 baseline, tablet layout, diff rendering, HTML/Markdown rendering and editing, data layer, Kanban drag-and-drop, push backend, store considerations, folder structure |
| [04-competitive-landscape.md](04-competitive-landscape.md) | Microsoft's mobile story, third-party apps, GitHub and Jira benchmarks, demand signals, MVP proposal |
| [05-pitfalls-and-risks.md](05-pitfalls-and-risks.md) | 24-row risk register, org and tenant policies, Conditional Access, throttling, PR review hard problems, work item complexity, board reconstruction, notifications, store and legal, deprecation calendar |
| [06-notification-relay-and-extension.md](06-notification-relay-and-extension.md) | Design sketch for push notifications via a Marketplace extension and a relay in the customer's Azure tenancy |
| [07-naming-candidates.md](07-naming-candidates.md) | Brand name shortlist with store, domain and trademark conflict checks |
| [verification/probe-public-api.sh](verification/probe-public-api.sh) | Reproducible anonymous probes against public projects |
| [verification/probe-results.txt](verification/probe-results.txt) | Captured output from 2026-09-10 |

**Deprecation dates that constrain the plan:** legacy Azure DevOps OAuth closed to new apps 2025-04-23 and retires in 2026 (exact date unpublished); global PATs stop working 2026-12-01; public projects become private in 2027; preview API revisions can be deactivated 12 weeks after the GA version ships.
