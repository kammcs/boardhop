# 08b — Flutter evaluation for Boardhop

**Date:** 2026-09-10. Compiled from four research passes (MSAL packages, Azure DevOps API clients and the Az DevOps competitor, UI building blocks, delivery and ecosystem health). Package data was pulled live from pub.dev and GitHub on this date. Claims not confirmed against a primary source are marked **unverified**.

**Team skills assumption:** kammcs has shipped production Flutter apps (two in 2024, using `flutter_quill`, `super_drag_and_drop`, `code_text_field`, `flutter_highlight`, `firebase_messaging`, bloc, go_router, drift, `flutter_secure_storage`) as well as TypeScript work. Skills are treated as "both", not "TypeScript-heavy".

---

## Executive summary

Flutter is a credible foundation for Boardhop, and on the single most important axis, **enterprise sign-in with the Microsoft Authenticator broker**, it is in materially better shape than React Native: `msal_auth` on pub.dev is an actively maintained native MSAL wrapper with documented broker support, full pub points, and a release two weeks ago. React Native has nothing comparable; every MSAL wrapper there is archived. Neither ecosystem has a Microsoft-authored SDK, so both carry third-party-maintainer risk, but Flutter's is live and React Native's is dead.

On UI, Flutter has what the app needs, with the same two custom-build items React Native has (a line-commentable diff viewer and a cross-column Kanban board), and one extra caution: work item descriptions are HTML, `flutter_quill` stores Quill Delta, and the Delta-to-HTML converters are stale, so rich-text fidelity needs real QA. Read-only HTML and Markdown rendering are well covered.

The Az DevOps competitor proves the whole feature set can be built in Flutter with a hand-rolled REST layer, but it appears dormant since December 2025, relies on private forks, and its PAT path is broken because it calls internal web endpoints. That is a gap to exploit, not a codebase to copy.

Flutter's structural costs versus Expo are the lack of first-party over-the-air updates (Shorebird is a four-person company), a recurring pattern of iOS text-input and VoiceOver bugs, and a smaller hiring pool. Ecosystem health is stable: quarterly releases, Impeller now default everywhere, 93 percent satisfaction in Flutter's own survey, but trust in Google as steward is only 62 percent and the Dart macros feature was cancelled after two years.

---

## Scorecard

| Criterion | Flutter status | Maturity (1–5) | Notes |
|---|---|---|---|
| Entra sign-in with broker | `msal_auth` 3.5.3 wraps MSAL Android 8.3 and MSAL iOS 2.14.1, Authenticator broker selectable | 4 | Third-party (Aubergine Solutions), one primary maintainer, broker bugs #128 and #142 fixed. No claims-challenge (CAE) API exposed. |
| Intune App Protection SDK | None, official or community | 1 | Same as React Native. Only .NET MAUI and native have it. |
| Azure DevOps client library | None maintained; `azure_devops_sdk` is a 7-year-old Dart 2 scaffold | 1 | Hand-write the REST layer (Az DevOps did, 91 KB) or generate from the OpenAPI spec. Same situation as React Native. |
| Kanban drag-and-drop across columns | `drag_and_drop_lists` 0.4.2 (457 likes) or `appflowy_board` 0.1.2 | 3 | All candidates 13 to 29 months stale. The team's own `super_drag_and_drop` experience applies. Custom polish expected. |
| Rich-text HTML editing | `flutter_quill` 11.5.1 (2.15k likes, May 2026) plus Delta↔HTML converters | 3 | Editor is first-class; the converters (`vsc_quill_delta_to_html` June 2024, `flutter_quill_delta_from_html`) are the weak link. `html_editor_enhanced` (WebView, Summernote) is the native-HTML fallback. |
| HTML rendering | `flutter_widget_from_html` 0.17.4, published 2 days ago | 5 | Prefer over `flutter_html` (18 months stale, 90 pub points). |
| Markdown rendering | `flutter_markdown_plus` 1.0.12 | 4 | `flutter_markdown` was discontinued by the Flutter team in May 2025; this is the designated successor. |
| Syntax highlighting | `re_highlight` (highlight.js 11.9 port) | 3 | `flutter_highlight` is 5.5 years stale. `flutter_code_editor` 0.3.5 is a maintained reference for line numbers and highlighting plumbing. |
| Diff viewer with line comments | None on pub.dev | 2 | Custom build on `diff_match_patch` plus `ListView.builder` or `super_sliver_list`. Same custom scope as React Native. |
| Large virtualized lists | `ListView.builder`; `super_sliver_list` 0.4.1 for variable-height thousands of rows | 4 | `super_sliver_list` is 30 months stale but stable. |
| Tablet and iPad layouts | SDK `NavigationRail`, `LayoutBuilder`; official large-screen guidance | 3 | `flutter_adaptive_scaffold` discontinued May 2025. iPad multi-window (issue #48838) open since 2020. Split View orientation bugs fixed. |
| Secure storage | `flutter_secure_storage` 11.1.0, published today | 5 | Keychain and Keystore; disable Android auto-backup. |
| Offline database | `drift` 2.35.0 (18 hours old), `sqflite` 2.4.4 | 5 | Avoid `isar` and `hive` originals (abandoned); `hive_ce` is the credible fork. Team already uses drift. |
| Push notifications | `firebase_messaging` 16.6.0 (Firebase-published), `flutter_local_notifications` 22.3.0 | 4 | Recurring iOS background-handler regressions (2021, 2024, 2025), all fixed. Standard APNs and FCM setup. |
| Over-the-air updates | No first-party mechanism; Shorebird (4 people, $3M seed Sept 2025) | 2 | Expo's EAS Update is the one thing Flutter cannot match. Store-policy compliance of patching compiled Dart is untested by enforcement (**unverified**). |
| Hot reload and tooling | Strong; agentic hot reload in 3.44; one 2025 benchmark regression | 4 | |
| CI | macOS runners required for iOS (as everywhere); 6 to 12 minute iOS release builds | 4 | |
| Rendering engine | Impeller default on iOS and Android; Skia removed in 3.44 | 4 | OpenGL ES fallback path had visual bugs on older Mali GPUs into mid-2026. |
| iOS text input and accessibility | Recurring bug category; keyboard overlap issue open since 2023; accessibility-tree regression filed May 2026 | 3 | Structural: Flutter reimplements text editing and the accessibility tree rather than using native views. |
| Ecosystem health | Quarterly cadence, 3.47 current; 93 percent satisfaction, 62 percent trust in Google; Flock fork small; macros cancelled Jan 2025 | 4 | The 2024 layoffs are the documented event; no separate 2025 Flutter layoff was found. |
| Hiring pool | Smaller than React Native; salary premium claimed (**unverified** multipliers) | 3 | Mitigated by kammcs's existing Flutter experience. |

---

## 1. MSAL and Entra ID on Flutter

Microsoft does not publish an MSAL for Flutter or Dart. The MSAL overview lists .NET, JavaScript, Java, Python, Android, iOS/macOS and Go; the AzureAD GitHub org has no Flutter repository; Microsoft Q&A points developers at community wrappers.

| Package | Version | Published | Publisher | Wraps native MSAL | Broker | Verdict |
|---|---|---|---|---|---|---|
| **`msal_auth`** | 3.5.3 | ~2026-08-26 | Aubergine Solutions (verified) | Yes: MSAL Android 8.3.+, MSAL iOS 2.14.1 pinned | Yes: Authenticator, browser, or WebView selectable; macOS too | **Pick this.** 160/160 pub points, 18.8k weekly downloads, 7 open issues, active CHANGELOG. |
| `msal_flutter` | 2.0.1 | ~2022 | muljin (verified) | Yes | Unclear | Repo archived. Dead. |
| `msal_auth_plugin` | 1.0.2 | ~2025-11 | LiquidLab (unverified) | Yes | Claimed | Tiny adoption. Backup only. |
| `azure_ad_authentication` | 1.0.5 | ~2023 | unverified | Yes, stale SDK pins | Undocumented | Not recommended. |
| `aad_oauth` | 1.0.1 | ~2024 | earlybyte (verified) | No: WebView OAuth flow | No | Cannot satisfy device-compliance Conditional Access. |
| `flutter_appauth` | 12.1.0 | ~2026-08-29 | dexterx.dev (verified) | No: AppAuth | No | Excellent for plain OIDC; wrong tool for broker. |
| `msal_mobile`, `msal_flutter_auth`, `flutter_azure_b2c`, `entra_id_dart_auth_sdk` | various | 2 to 6 years stale, or server-side only | | | | Not applicable. |

`msal_auth` details that matter for Boardhop:

- `acquireToken` with prompt selection, `acquireTokenSilent` with `MsalUiRequiredException`, single- and multi-account modes, custom authority per tenant.
- PKCE is handled inside native MSAL (not documented at the plugin level, **unverified** as an explicit guarantee).
- **No claims-challenge or CAE API is exposed.** Native MSAL supports it; the plugin does not surface it. Boardhop would need to fork or add a platform channel if CAE step-up becomes a hard requirement. This is the one functional gap versus a hand-built native module.
- History of broker-path bugs, since fixed: #128 (Android broker auth failure), #142 (shared-device-mode crash), #125 (B2C `expiresOn` nil crash). Budget QA time on the broker path.
- Fork contingency: the Az DevOps competitor already runs on a private fork, which shows both that forking is feasible and that the upstream cadence has not always satisfied real users.

**Risk relative to React Native.** Comparable in kind (third-party, small team, no Microsoft SLA), better in timing: `react-native-msal` was archived in May 2022 and its sibling in 2023. On React Native the choice is "build a native module from scratch"; on Flutter it is "adopt and possibly fork a living package".

## 2. Intune App Protection Policies

No Intune App SDK exists for Flutter, official or community. Tenants that require an app protection policy for Azure DevOps cannot use a Flutter Boardhop, exactly as with React Native. Only .NET MAUI (see 08a) and native apps can reach that segment.

## 3. Azure DevOps API on Flutter, and the Az DevOps competitor

**No maintained Dart client exists.** `azure_devops_sdk` is a single-release, Dart-3-incompatible OpenAPI scaffold from 2019 against API 5.1. Microsoft ships first-party SDKs for .NET, Node, Python, Go and Rust, not Dart. Boardhop hand-writes the REST layer either way; the spike scripts in `research/spikes/` already define the calls.

**Az DevOps (Purplesoft, MIT, github.com/PurpleSoftSrl/azure_devops_app):**

- 166 stars, 57 forks, 12 open issues. Created January 2023. **Last commit 2025-12-12**, roughly nine months ago, while issues kept arriving through August 2026. One contributor made 635 of 649 contributions.
- Auth: `msal_auth` from a **private Purplesoft fork**, single-account mode, scope `499b84ac-…/user_impersonation`, optional authority for multi-tenant; plus a PAT flow. **Issue #73 (2026-08-03): Boards and Sprints fail with PAT because those screens call internal web-UI endpoints that reject PATs.** Issue #67 (2026-02): work item creation fails outright. Both open.
- Diffs: fetched pre-computed from an endpoint the maintainers call `getCommitDiff`, rendered as plain `Text` with red and green backgrounds, **no syntax highlighting**. Combined with #73, this strongly suggests use of the undocumented `_api/_versioncontrol/fileDiff` endpoint that document 01 warns against (**unverified** which endpoint exactly).
- Rendering: `flutter_html` from a private fork for HTML, `flutter_markdown` (discontinued) for Markdown, `flutter_highlighting` fork for full-file view, `html_editor_enhanced` for composing.
- No state-management package; custom InheritedWidget services. `http` plus one 91 KB `azure_api_service.dart`. `shared_preferences` for storage. Sentry, Firebase Analytics, Google and Amazon ads, RevenueCat.
- Features: boards, sprints, work items with saved queries, PRs with file diff, commits, pipelines with logs, multi-org. **No wiki, no push notifications** (issue #68 open).
- App Store 4.4 to 4.5 stars on roughly 50 ratings; Play numbers not extractable (**unverified**).

What it proves: the full Boardhop feature set is buildable in Flutter by one person. What it leaves open: syntax-highlighted diffs, correct PAT-safe public API usage, push, wiki, and an actively maintained product. Its dormancy is a market opening.

## 4. UI building blocks

**Kanban.** `drag_and_drop_lists` (457 likes, 150 points, cross-list reorder, 22 months stale) is the most capable general option; `appflowy_board` (225 likes, purpose-built, 29 months stale, no web) the closest semantic fit. Both need polish for a Jira-quality swipe and drag experience. The team's prior `super_drag_and_drop` work is directly reusable.

**Rich text editing.** `flutter_quill` is the dominant editor (242k weekly downloads, published May 2026) but stores Delta, and its own docs discourage storing as HTML. Converters: `vsc_quill_delta_to_html` (June 2024) and `flutter_quill_delta_from_html` (13 months). Expect fidelity loss on nested tables and unusual inline styles; the safeguards in the summary (format detection, never convert, `validateOnly`, `test /rev`) still apply. `html_editor_enhanced` (Summernote in a WebView, 660 likes, 14 months) handles HTML natively at the cost of a WebView. `fleather` (published 17 days ago) is the best-maintained Delta editor but small. `super_editor` is pre-1.0 with dev-channel churn. `appflowy_editor` is AGPL/MPL dual-licensed; legal review before use.

**Read-only rendering.** `flutter_widget_from_html` (150 points, published 2026-09-08) for HTML; `flutter_markdown_plus` for Markdown, the Flutter team's named successor after discontinuing `flutter_markdown`. Both handle the mention forms and embedded images, provided images are fetched with an Authorization header (custom image builder).

**Diffs.** No line-commentable diff viewer exists on pub.dev. Compute with `diff_match_patch` (Google's algorithm, unmaintained but complete), highlight with `re_highlight`, render with `ListView.builder` or `super_sliver_list`, borrow line-number and gutter plumbing from `flutter_code_editor`. Custom scope, identical in size to the React Native plan.

**Adaptive layouts.** Build on SDK widgets (`NavigationRail`, `LayoutBuilder`, `MediaQuery`) following the official large-screens guide. `flutter_adaptive_scaffold` was discontinued in May 2025 and its forks are too small to trust. iPad multi-window remains open (#48838). This matches the "responsive phone layout at launch" decision.

**Storage.** `flutter_secure_storage` 11.1.0 (published today) for tokens; `drift` for the offline cache and write queue. Avoid original `isar` and `hive`.

## 5. Push notifications

`firebase_messaging` 16.6.0 is Firebase-published, Flutter Favorite, and standard. Constraints are platform-level and identical across frameworks: no simulator testing, swipe-away on iOS stops background delivery, Doze delays normal-priority data messages on Android, and the background handler must be a top-level function with `@pragma('vm:entry-point')`. FlutterFire has had three separate "background handler not invoked on iOS" regressions (2021, 2024, 2025), all resolved. The tenant relay from document 06 is unchanged by the framework choice.

## 6. Developer experience and delivery

- Hot reload is strong and still invested in (web parity in 3.35, agentic hot reload in 3.44), with one documented benchmark regression in July 2025.
- iOS release builds run 6 to 12 minutes on GitHub Actions or Codemagic Apple-silicon runners.
- **No first-party OTA.** Apple 2.5.2 and Google's policies permit interpreted-code updates, which is why Expo's EAS Update is legitimate, and forbid compiled-code changes. Shorebird patches Dart AOT and claims compliance (**unverified** against enforcement), is run by about four people, raised $3M in September 2025, and prices from free (5k installs) to $400 a month (1M installs). Treat as a nice-to-have with vendor risk, not a platform guarantee.
- Impeller is the only renderer since 3.44 (May 2026); the OpenGL ES fallback for non-Vulkan Android devices has had gradient and WebView-blurriness bugs into mid-2026.
- iOS text input and VoiceOver are a recurring bug category: keyboard overlap after native dialogs open since August 2023, an accessibility-tree loss regression filed May 2026. Boardhop's comment composers and the rich-text editor sit right on this seam. Plan for real-device QA on iOS text fields.
- Binary size: inconsistent across sources; Flutter ships its own engine; expect tens of MB either way (**unverified** ranges).

## 7. Ecosystem health

- Releases: 3.35 (Aug 2025), 3.38 (Nov 2025), 3.41 (early 2026), 3.44 (May 2026), 3.47 (Aug 2026, current). Quarterly, unbroken.
- The documented Google layoff affecting Flutter and Dart was April to May 2024. No distinct 2025 Flutter layoff was found; claims of one appear to recycle the 2024 event.
- Flock, the ex-Googler fork announced October 2024, has 382 stars and a December 2025 last push. Niche, not a threat or an alternative.
- Dart macros were cancelled on 2025-01-29 after two years, redirecting to smaller serialization features. A data point on roadmap risk, not on runtime stability.
- Flutter's Q2 2026 survey (3,500 respondents, self-selected): 93 percent satisfied, 83 percent trust Flutter, **62 percent trust Google**, Cupertino widgets the weakest area at 61 percent.
- Market share figures (46 percent Flutter versus 35 to 38 percent React Native) and hiring multipliers come from SEO comparison blogs and are **unverified**; the direction (Flutter widely used, React Native's hiring pool larger) is consistent across sources.

## 8. Verdict for Boardhop

**Where Flutter beats React Native/Expo**

- Broker-capable MSAL exists today and is maintained. This is the decisive item given the decision to ship broker support in v1.
- One rendering engine on both platforms: boards, drag-and-drop and diff rendering behave identically on iOS and Android.
- No New Architecture migration churn; no Expo dev-client versus Expo Go split.
- kammcs has shipped two Flutter apps with most of the relevant packages.

**Where Flutter loses**

- No first-party OTA updates. Every fix is a store release unless Shorebird is adopted.
- iOS text editing and accessibility are reimplemented rather than native, and bugs recur there.
- Rich-text HTML editing goes through Delta conversion or a WebView.
- Smaller hiring pool if the team grows.

**Where they tie**

- No Microsoft SDK for either. No Intune SDK for either. No Azure DevOps client library for either. Diff viewer and Kanban are custom in both.

**Relative effort.** Roughly equal for the app itself. The auth work is smaller on Flutter (adopt `msal_auth`, harden the broker path, add a CAE hook if needed) than on React Native (write and maintain a native MSAL module). The rich-text editor is somewhat larger on Flutter because of Delta conversion. Net, Flutter is the shorter path for Boardhop as scoped, provided the team accepts store-release-only updates or Shorebird's vendor risk.

---

## Citations

- pub.dev packages: `msal_auth`, `msal_flutter`, `aad_oauth`, `flutter_appauth`, `azure_ad_authentication`, `msal_mobile`, `msal_auth_plugin`, `azure_devops_sdk`, `drag_and_drop_lists`, `appflowy_board`, `boardview`, `kanban_board`, `flutter_boardview`, `flutter_quill`, `vsc_quill_delta_to_html`, `flutter_quill_delta_from_html`, `html_editor_enhanced`, `super_editor`, `fleather`, `appflowy_editor`, `flutter_html`, `flutter_widget_from_html`, `flutter_markdown`, `flutter_markdown_plus`, `markdown_widget`, `gpt_markdown`, `flutter_highlight`, `re_highlight`, `flutter_code_editor`, `code_text_field`, `diff_match_patch`, `pretty_diff_text`, `super_sliver_list`, `flutter_adaptive_scaffold`, `flutter_secure_storage`, `drift`, `sqflite`, `isar`, `isar_community`, `hive`, `hive_ce`, `firebase_messaging`, `flutter_local_notifications` (all at https://pub.dev/packages/<name>, fetched 2026-09-10)
- https://github.com/nayanAubie/msal_auth and its issues #128, #142, #125, #131
- https://learn.microsoft.com/en-us/entra/identity-platform/msal-overview
- https://learn.microsoft.com/en-us/answers/questions/770083/flutter-azure-ad-integration
- https://github.com/AzureAD
- https://github.com/stashenergy/react-native-msal (archived 2022-05-20)
- https://github.com/PurpleSoftSrl/azure_devops_app (repo, commits, issues #73, #72, #71, #70, #69, #68, #67, #65, #63; pubspec.yaml; lib/src/services/msal_service.dart; lib/src/screens/file_diff/components_file_diff.dart)
- https://github.com/sowderca/azure_devops_sdk
- https://github.com/microsoft/azure-devops-node-api, -python-api, -go-api, -rust-api
- https://docs.flutter.dev/ui/adaptive-responsive and /large-screens
- https://github.com/flutter/flutter/issues/162965 (adaptive scaffold fork coordination), #48838, #133537, #186582, #151240, #179268, #187505, #171722
- https://flutter.dev/blog/flutter-q2-2026-survey
- https://blog.flutter.dev/whats-new-in-flutter-3-35-c58ef72e3766, https://flutter.dev/blog/whats-new-in-flutter-3-38, https://flutter.dev/blog/whats-new-in-flutter-3-44, https://flutter.dev/blog/whats-new-in-flutter-3-47
- https://dart.dev/blog/an-update-on-dart-macros-data-serialization
- https://techcrunch.com/2024/05/01/google-lays-off-staff-from-flutter-dart-python-weeks-before-its-developer-conference/
- https://github.com/join-the-flock/flock
- https://shorebird.dev/pricing, https://shorebird.dev/blog/seed-round, https://www.accel.com/news/supercharging-flutter-developers-our-investment-in-shorebird
- https://bitrise.io/blog/post/what-app-stores-allow-with-ota-updates-apple-and-google-policy-explained
- https://blog.codemagic.io/build-speed-benchmark-comparison/
- https://firebase.google.com/docs/cloud-messaging/flutter/client, https://github.com/firebase/flutterfire/issues/6290, #13643, #13442, #6388, #4718
- https://docs.flutter.dev/perf/impeller
