# Spike results — 2026-09-10

Run against `https://dev.azure.com/puremedia`, project "CloudCover 2.0", with Kelly's PAT (read-only calls plus two `validateOnly=true` dry runs that saved nothing). Raw evidence is in the sibling files. Total cost of the whole run was under 4 TSTU against a 200 TSTU budget.

## Findings that change the plan

| # | Question | Answer | Consequence |
|---|---|---|---|
| S4 | Is there an org-level PR list? | **Yes.** `GET {org}/_apis/git/pullrequests?searchCriteria.reviewerId=…&searchCriteria.status=active` returns 200 with PRs across projects. Undocumented, so treat as best-effort with per-project fan-out as the fallback. | The review inbox is one call, not one per project. Document 01's gap is wrong in practice. |
| S5 / S5b | How do we tell HTML from Markdown on a work item? | **`multilineFieldsFormat` is returned at plain `api-version=7.1`** on single GET, list GET and `workitemsbatch`, as long as the request does **not** pass a `fields` filter (or passes `$expand=all` on the batch). With a `fields` list it comes back empty. Values seen: `{"System.Description": "html", "System.History": "html", "Microsoft.VSTS.Common.AcceptanceCriteria": "html"}`. Some items carry no map at all. | No 7.2-preview dependency needed. Documents 01 and 05 were both wrong. Fetch the item for the editor without a `fields` filter. `workitemsbatch` at `7.2-preview.3` returns 400, so pin batch to 7.1. Treat a missing map as HTML. |
| S10 | Can the WEF field names be derived from the board id? | **No.** Board id `231ed315-…` but the fields are `WEF_B68E37FC957543E5B806D5F614F5A6AE_Kanban.*`. | Always read `board.fields.{columnField,rowField,doneField}.referenceName`. Document 01's inference was wrong. |
| S10 | What do card settings and rule settings look like? | Captured raw. `cardsettings.cards` is a per-type array of `{fieldIdentifier, displayType?}` entries plus a `{showEmptyFields}` entry mixed into the same array. `cardrulesettings.rules.fill[]` has `filter` (WIQL-ish string), `clauses[]`, and `settings.background-color` / `title-color`; `rules.tagStyle[]` has `name` and `settings.background-color`. `isEnabled` is the string `"True"`. | Enough to render card fields and colours faithfully. Pin to this shape and parse defensively. |
| S11 | Does `validateOnly=true` give usable errors? | **Yes.** HTTP 400 with `customProperties.RuleValidationErrors[]` carrying `fieldReferenceName`, `fieldStatusFlags` (for example `required, hasValues, limitedToValues, invalidListValue`) and a human message. A stale `test /rev` returns **HTTP 412** `VS403351`. | Dynamic forms can show field-level errors before saving. The offline write queue maps 412 to the conflict screen. |
| S11 | What does field metadata cost? | `workitemtypes/Bug/fields?$expand=All` cost **1.12 TSTU** and returned 71 fields with `allowedValues`, `alwaysRequired` and `dependentFields`. `System.State` lists 12 dependent fields. | Cache per project and type for 24 h. Never fetch on every form open. |
| S9 | What does one Activity poll cycle cost? | About **0.013 TSTU** for three projects (PR list per project, one org-wide WIQL, one batch, one reporting-feed page). Git and build endpoints report no `X-RateLimit-Cost` at all. | Polling every 60 s in the foreground is two orders of magnitude under budget. |
| S2 / S2b | Do PATs work against the profile and accounts APIs? | **Inconclusive for the doc conflict**, because this PAT lacks the profile scope: `app.vssps.visualstudio.com/_apis/profile/profiles/me` returns 401 with only a `Basic` challenge. But **`https://vssps.dev.azure.com/{org}/_apis/profile/profiles/me` returns 200** with this PAT, including `id`, `publicAlias` and email. `connectionData` also returns the identity GUID. | Org-scoped identity is available without the profile scope. Re-test the accounts API with a PAT that has `vso.profile` before relying on it. Not needed for launch since v1 is Entra-only. |
| S6 | What is the suggested-change wire format? | No suggestion comments exist in the last 40 PRs (186 threads, 32 file-anchored). Captured a reference file-anchored thread: `threadContext.filePath` plus `rightFileStart/End {line, offset}` and `pullRequestThreadContext {iterationContext {first, second}, changeTrackingId}`. | Still needs the write half on a scratch PR. |

## Smaller observations

- This PAT reaches work, code, wiki, search, service hooks, favorites and teams, and is denied on build, pipelines, release, Graph, identities, notification subscriptions, extension management and entitlements. A read-only PAT for future spikes should add `vso.build`, `vso.graph`, `vso.notification`, `vso.profile` and `vso.extension`.
- `GET {org}/_apis/teams?$mine=true` at `7.1-preview.3` works and returned three teams across the org in one call.
- `wit/workitems` accepts `7.1`, `7.2-preview.2` and `7.2-preview.3`; `7.2-preview.4` returns a clean `VssVersionOutOfRangeException` (400).
- Work item 15433's description contains entity-escaped HTML (`&lt;p&gt;…`), presumably written through an integration. The renderer must not crash on escaped markup and should probably show it as text.
- Test Case work items carry no board fields; the board query must filter to the backlog's work item types.
- `canEdit` was `false` on the Stories board for this user, so board configuration writes must be gated on it.
- The "CloudCover 2.0" process is a customised Agile process: ten User Story states, custom types (Tech Task, QA Task, Bug Task), and custom fields (`Custom.QAStoryPoints`, `Custom.QAAssignee`). A good stress test for dynamic forms.

## Write spikes (scratch project "DevOps Mobile App", 2026-09-10)

Work items #15503–#15507 were created and left in place for inspection.

| # | Question | Answer | Consequence |
|---|---|---|---|
| w01 | Does the Markdown write path work? | **Yes.** Creating with `/multilineFieldsFormat/System.Description = Markdown` stores raw Markdown and reads back `"markdown"`. Creating with plain HTML reads back `"html"` immediately, so the map is populated from the first save. | The editor can rely on the map being present on any item saved through the API. |
| w01 | Is the conversion really irreversible? | **Not through the REST API.** Converting HTML→Markdown succeeded, and a later patch with `Html` plus HTML content also succeeded (HTTP 200, format back to `"html"`). Microsoft's "no way to revert" statement describes the web UI. | Still never convert silently. But an accidental conversion is recoverable through the API, which lowers the risk of the rich-text decision. |
| w01 | Does editing a Markdown field without the format op keep the format? | **Yes.** The field stayed `"markdown"`. | The editor only needs to send the format op when changing format. |
| w01 | Does the preview Comments API handle Markdown? | **Yes.** `POST …/comments?format=markdown` at `7.1-preview.4` stores Markdown and returns `renderedText` as HTML. `$expand=renderedText` on the list works. | Render comments from `renderedText` and never reimplement the Markdown dialect. |
| w02 | Does writing the WEF column field auto-derive `System.State`? | **Yes.** Patching only the column to "Active" set State to Active and Reason to "Implementation started". Patching only State to "Active" set the column to Active. Column-only to "Closed" set State to Closed. | Either field alone is enough. Sending both in one patch remains the safe choice and costs nothing. Document 01's "undocumented, send both" advice holds. |
| w02 | What does an invalid column name do? | HTTP 400 with a rule error on `System.State` (`TF401320`), not on the column field. | Validate the column name client-side against `board.columns` and map the error back to the card, not to a state picker. |
| w02 | Can `Column.Done` be set on a non-split column? | **Accepted silently** (HTTP 200, `Done` became true on the "Active" column). | Never send the Done op unless the target column has `isSplit`. |
| w02 | Is `System.BoardColumn` writable? | **No.** HTTP 400 `TF401326: Invalid field status 'ReadOnly'`. | Confirms the WEF field is the only write path. |
| w02 | Does `validateOnly=true` work for a column move? | **Yes.** Returned 200 and changed nothing. | Use it for drag previews if desired. |
| w03 | Can a whole PR be seeded through REST? | **Yes.** Initial push to an empty repo with the zero `oldObjectId` works. A new branch must be created as a ref first (`POST refs` with `newObjectId` = base commit); a push that both creates the ref and edits a file fails with "path does not exist at commit 0000…". PR create, thread create, vote and label all worked. | The app never needs this, but the test harness does. |
| w03 | Does a line comment posted with `changeTrackingId` survive a push that shifts lines? | **Yes, and the tracked position is only returned on request.** After inserting three lines at the top, the default threads read still returns the original `line: 6`. Reading with `$iteration=2&$baseIteration=0` returns `rightFileStart.line: 9` plus `trackingCriteria` carrying the original position, and the end offset becomes `2147483647` (whole line). | Always read threads with `$iteration` and `$baseIteration` matching the diff being shown, then overlay by the returned `threadContext`. The default read is only correct for the iteration the comment was posted on. |
| w03 | Can the PR author vote? | **Yes.** `PUT reviewers/{me}` with `vote: 5` returned 200 for the creator. | No special casing for self-review. |
| w03 | Suggestion wire format | **Settled.** A comment whose `content` is Markdown with a ```` ```suggestion ```` fence, anchored to the target line through `threadContext` on the right side, renders in the web UI as an applyable suggestion. Kelly confirmed thread 42376 on PR 8319 showed the Apply flow (2026-09-10). | The mobile composer emits the GitHub-style fence in the comment body; no special API field exists. Anchor to the right-hand side only, since the web UI offers no suggestion on left-side lines. |
| S2 (revisited) | With the broadened PAT, do the `app.vssps.visualstudio.com` profile and accounts APIs work? | **Still 401** with only a `Basic` challenge, while Graph, entitlements and every other area now return 200. This supports Microsoft's 2026-09-04 statement that these two APIs accept only Entra tokens. `vssps.dev.azure.com/{org}/_apis/profile/profiles/me` keeps working with a PAT. | PAT login (roadmap) cannot enumerate orgs; it must be per-org. Already the design. |

## Still to run

| Spike | Needs |
|---|---|
| Service hook "Minimal" payload capture | Project-admin rights on the scratch project and an HTTPS receiver |
| Token sizes, cross-tenant 401 hint | Entra app registration and a guest account |

## F1: msal_auth sign-in on Android (2026-09-10)

Pixel 10 Pro emulator, Android 17, no Authenticator (browser fallback). Interactive sign-in through a Chrome custom tab succeeded; after `am force-stop` the app restored the session silently. Access token 2,051 bytes, 75-minute lifetime, issued for the puremedia tenant with ten `vso.*` scopes from `.default`. `app.vssps` `profiles/me` and `accounts?memberId` worked with the Entra token (one org), `dev.azure.com/puremedia/_apis/projects` returned four projects, and the org-scoped `vssps` profile matched. `X-RateLimit-Cost` 0.0036 on the projects call. Emulator needed `-dns-server 8.8.8.8,1.1.1.1` on this host. Raw report: `f1-device-run.md` (gitignored).
