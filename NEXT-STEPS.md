# Boardhop — state and next steps

**As of:** 2026-09-10, end of the discovery session.
**Read first:** [research/00-feasibility-summary.md](research/00-feasibility-summary.md) section 0 (decisions) and 6a (spike results), then [research/08-stack-comparison.md](research/08-stack-comparison.md).

## Where things stand

| Area | State |
|---|---|
| Product | Boardhop: Flutter mobile client for Azure DevOps Services, iOS + Android, phones + tablets. Jira-style boards and work items, GitHub-style PR review. |
| Stack | **Flutter**, locked 2026-09-10. `msal_auth` for Entra sign-in with the Authenticator broker; `drift` for offline cache and write queue; `flutter_quill` or `html_editor_enhanced` for rich text (to be chosen by spike); `flutter_widget_from_html` and `flutter_markdown_plus` for rendering; `diff_match_patch` + `re_highlight` + custom diff viewer. |
| Scope | Entra OAuth only at launch (no PAT). Cloud only. Read plus lightweight writes in v1. Responsive tablet layout, multi-pane later. Free app; revenue via a Marketplace extension plus a relay in the customer's Azure tenancy. Build order: work items and boards, then PR review, then pipelines. |
| Research | Documents 01–09 in `research/`, all committed. Spike scripts and consolidated results in `research/spikes/` (raw result files are gitignored: client data). |
| Spikes done | Org-level PR list exists; `multilineFieldsFormat` returned at 7.1 without a `fields` filter; WEF column write derives State; `validateOnly` gives field-level errors; stale rev → 412; line comments track across pushes when read with `$iteration`/`$baseIteration`; ```` ```suggestion ```` fence renders as an applyable suggestion; poll cycle ≈ 0.013 TSTU; profile/accounts APIs on `app.vssps` are Entra-only. |
| Entra | kammcs tenant exists (from the Multipass code-signing project). **Boardhop registration created** as multi-tenant public client with Azure DevOps delegated permissions (`vso.threads_full` is not offered in Entra; `vso.code_write` covers PR threads). **Puremedia admin consent granted** for tenant `342d4cd1-7ea8-4452-8ceb-542b71d159f6` (verified domain `cloudcover.it`); the trailing browser error was the redirect to the `msauth` URI, not a failure. |
| Test org | `https://dev.azure.com/puremedia`, project "CloudCover 2.0" for read tests; scratch project **"DevOps Mobile App"** for writes (work items #15503–#15507 and PR 8319 left there). PAT in the AzureDevOps MCP config is authorized for spikes; it now has near-full scopes. |
| Repo | `git@github.com:kammcs/boardhop.git`, branch `main`. Commit and push are pre-approved. |
| Still administrative | Partner Center + MPN ID for publisher verification; Visual Studio Marketplace publisher; Apple and Google developer accounts; privacy policy; domain for boardhop. |

## Values needed from Kelly

- **Entra client ID** of the Boardhop registration (not yet recorded anywhere; keep it out of the public repo, put it in a gitignored `.env` or `--dart-define`).
- Confirmation that `msauth.com.kammcs.boardhop://auth` and the Android debug redirect `msauth://com.kammcs.boardhop/%2F%2Fksb0DQrePXmmxPydZ%2FUbpze98%3D` are saved on the registration.
- A test device with Microsoft Authenticator signed in to the puremedia tenant (iOS or Android).

## Next steps, in order

1. **Scaffold the Flutter app** in this repo (`flutter create` with org `com.kammcs`, package `com.kammcs.boardhop`; Flutter from `C:\Users\sixfe\Projects\flutter\flutter\bin`). Structure: `lib/core` (http client with per-service host routing, api-version pinned per call, rate-limit header handling), `lib/auth` (`msal_auth` wrapper, per-tenant account cache), `lib/data` (drift schema, repositories), `lib/features/{work_items,boards,pull_requests,pipelines,activity}`, go_router, bloc. Add CI later.
2. **Spike F1: `msal_auth` broker sign-in** against puremedia on a real device. Configure client ID, `organizations` authority, redirect URIs, Android `BrowserTabActivity` with the debug signature hash, iOS `LSApplicationQueriesSchemes` (`msauthv2`, `msauthv3`) and keychain group. Verify: interactive sign-in via Authenticator, `acquireTokenSilent` after restart, a call to `https://dev.azure.com/puremedia/_apis/projects?api-version=7.1` with the token, token byte size. Then call `app.vssps.visualstudio.com/_apis/profile/profiles/me` and `/_apis/accounts?memberId=` with the Entra token to confirm org discovery.
3. **Spike F2: claims-challenge path.** Confirm whether `msal_auth` can pass `claims` to native MSAL for Azure DevOps Continuous Access Evaluation; if not, fork or add a platform channel. Design the 401-with-`WWW-Authenticate`-claims handler in the http client either way.
4. **Spike F3: HTML round-trip.** Pull five real descriptions from CloudCover 2.0 (tables, nested lists, inline images, mentions), run through `flutter_quill` Delta conversion and `html_editor_enhanced`, diff the output, pick the editor.
5. **Spike F4: Kanban drag-and-drop** with `drag_and_drop_lists` (and the team's `super_drag_and_drop` experience): 200 cards, cross-column drop, haptics, auto-scroll, 60 fps on a phone.
6. **Spike F5: diff viewer prototype.** `diff_match_patch` + `re_highlight` + `super_sliver_list` on a 3,000-line file with a tap-to-comment gutter; threads read with `$iteration`/`$baseIteration`.
7. **Then the first milestone:** sign-in → org picker → project list → "assigned to me" work items → work item detail (render HTML/Markdown, comments) → board with column moves. Dogfood against puremedia.
8. **In parallel, administrative:** start Partner Center enrollment; register the boardhop domain; Apple/Google developer accounts.
9. **Later:** Marketplace extension + tenant relay (research/06), webhook payload capture spike, Intune plugin only if a customer requires it (research/08 §4).

## Conventions

- Never commit client IDs, tokens or raw spike results. `.gitignore` already excludes `research/spikes/results/*.md` except the README.
- Spikes against puremedia: writes only in the "DevOps Mobile App" project. Run with `python research/spikes/_run_with_mcp_creds.py <script>`.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Azure DevOps API: pin `api-version=7.1` per operation; read work items without a `fields` filter when the format map is needed; always send `test /rev`.
