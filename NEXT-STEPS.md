# Boardhop — state and next steps

**As of:** 2026-09-10, Flutter scaffold committed; spikes F1 and F2 passed on an Android emulator.
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
| Emulator | AVD `boardhop_pixel_10_pro` (Android 17, Play image). Start with `tool/start-emulator.ps1`; the `-dns-server` flag is required on this host. |
| Plugin fork | `packages/msal_auth` is a vendored, patched copy of msal_auth 3.5.3 (path dependency). Keep the diff small; see its README. |
| App scaffold | Done. Flutter 3.47.3 / Dart 3.13. `lib/core` (config, `AdoClient`, rate limits, typed errors), `lib/auth` (`AuthService` over `msal_auth` 3.5.3, `AuthBloc`), `lib/data` (drift: organizations, projects, pending_writes), `lib/features/*` (sign-in, org picker, project list, diagnostics; placeholders for work items, boards, PRs, pipelines, activity). Android: `assets/msal_config.json`, `BrowserTabActivity` with the hash from gitignored `android/secret.properties`. iOS: URL scheme, `LSApplicationQueriesSchemes`, keychain group entitlement, deployment target 16.0. 13 unit tests pass; `flutter analyze` is clean. |
| Still administrative | Partner Center + MPN ID for publisher verification; Visual Studio Marketplace publisher; Apple and Google developer accounts; privacy policy; domain for boardhop. |

## Values needed from Kelly

- ~~Entra client ID~~ Provided in the gitignored `.env` as `BOARDHOP_CLIENT_ID`; run with `--dart-define-from-file=.env`.
- Confirmation that `msauth.com.kammcs.boardhop://auth` and the Android debug redirect `msauth://com.kammcs.boardhop/%2F%2Fksb0DQrePXmmxPydZ%2FUbpze98%3D` are saved on the registration.
- A physical device with Microsoft Authenticator for the broker path and Conditional Access (the emulator run used the browser fallback).

## Next steps, in order

1. ~~**Scaffold the Flutter app**~~ Done (see the App scaffold row above). CI still to add.
2. ~~**Spike F1**~~ Passed 2026-09-10 on a Pixel 10 Pro / Android 17 emulator (`tool/start-emulator.ps1`, then `flutter run -d emulator-5554 --dart-define-from-file=.env`): browser-fallback sign-in, silent restore after force-stop, org discovery, 2 KB token with ten `vso.*` scopes, all diagnostics green. See `research/spikes/results/README.md`. Still open: the Authenticator broker path and iOS, which need a physical device.
3. ~~**Spike F2**~~ Done 2026-09-10. `msal_auth` is vendored at `packages/msal_auth` (3.5.3+boardhop.1) with `claims`, `forceRefresh` and `clientCapabilities` added; CP1 is declared; `AdoClient` retries a 401 once via `AuthService.resolveChallenge`. Emulator run: forceRefresh and claims requests both reach native MSAL. Token lifetime stays ~75 min with CP1 (no long-lived CAE tokens from Azure DevOps). Left open: trigger a real revocation to see an `insufficient_claims` 401 end to end; compile the Swift side on a Mac; offer the patch upstream.
4. **Spike F3: HTML round-trip.** Pull five real descriptions from CloudCover 2.0 (tables, nested lists, inline images, mentions), run through `flutter_quill` Delta conversion and `html_editor_enhanced`, diff the output, pick the editor.
5. **Spike F4: Kanban drag-and-drop** with `drag_and_drop_lists` (and the team's `super_drag_and_drop` experience): 200 cards, cross-column drop, haptics, auto-scroll, 60 fps on a phone.
6. **Spike F5: diff viewer prototype.** `diff_match_patch` + `re_highlight` + `super_sliver_list` on a 3,000-line file with a tap-to-comment gutter; threads read with `$iteration`/`$baseIteration`.
7. **Then the first milestone:** sign-in → org picker → project list → "assigned to me" work items → work item detail (render HTML/Markdown, comments) → board with column moves. Dogfood against puremedia.
8. **In parallel, administrative:** start Partner Center enrollment; register the boardhop domain; Apple/Google developer accounts.
9. **Later:** Marketplace extension + tenant relay (research/06), webhook payload capture spike, Intune plugin only if a customer requires it (research/08 §4).

## Conventions

- Never commit client IDs, tokens or raw spike results. `.gitignore` already excludes `research/spikes/results/*.md` except the README, plus `.env` and `android/secret.properties`.
- After changing drift tables run `dart run build_runner build`; the generated `app_database.g.dart` is committed.
- Spikes against puremedia: writes only in the "DevOps Mobile App" project. Run with `python research/spikes/_run_with_mcp_creds.py <script>`.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Azure DevOps API: pin `api-version=7.1` per operation; read work items without a `fields` filter when the format map is needed; always send `test /rev`.
