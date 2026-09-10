# 08 — Cross-platform stack comparison for Boardhop

**Date:** 2026-09-10
**Question:** Before committing to React Native/Expo, is there an easier glide path? Does Microsoft have a stack better suited to its own services, and is Flutter more mature for MSAL?
**Inputs:** [08a .NET MAUI](08a-dotnet-maui-evaluation.md), [08b Flutter](08b-flutter-evaluation.md), [08c React Native re-check and other stacks](08c-react-native-and-other-stacks.md), plus the original [03 Expo stack](03-expo-tech-stack.md) document and the decisions in [00](00-feasibility-summary.md).

**Team skills, verified on this machine:** twelve TypeScript projects, two production Flutter apps from 2024 (using `flutter_quill`, `super_drag_and_drop`, `code_text_field`, `flutter_highlight`, `firebase_messaging`, bloc, go_router, drift, `flutter_secure_storage`), one Android Gradle project, no C# projects. The MAUI and React Native evaluations were briefed with a "TypeScript-heavy" assumption; this comparison corrects for the Flutter experience.

---

## 1. Recommendation

**Switch to Flutter.** It is the shortest path to the product as scoped, for four reasons that compound:

1. **Broker-capable Entra sign-in exists today.** `msal_auth` wraps the current native MSAL SDKs with Microsoft Authenticator broker support, has full pub points, and shipped a release two weeks ago. On React Native every MSAL wrapper is archived, and the v1 plan required writing and maintaining a native Expo Module (three to six weeks plus ongoing SDK bumps, with no finished open-source example to copy).
2. **kammcs has shipped Flutter apps with most of Boardhop's building blocks.** Drag-and-drop, rich text, code highlighting, push, secure storage and an offline database are all packages the team has already used in production.
3. **One rendering engine on both platforms** for the two hardest screens, the Kanban board and the diff viewer. No New Architecture migration, no dev-client versus Expo Go split.
4. **It costs nothing on the Azure DevOps side.** No stack has a maintained Azure DevOps client library, and the REST layer, diff engine and board reconstruction are the same work everywhere. The spikes already done transfer unchanged.

**What Flutter gives up versus Expo:** first-party over-the-air updates (Shorebird is a four-person vendor), a recurring pattern of iOS text-input and VoiceOver bugs because Flutter draws its own text fields, HTML editing through Quill Delta conversion or a WebView, and a smaller hiring pool. None of these blocks the product. The OTA loss is the one to feel: every fix is a store release, so the release pipeline and TestFlight and Play internal tracks need to be smooth from day one.

**.NET MAUI is the answer to a different question.** It is the only cross-platform stack with a first-party Intune App Protection SDK and first-party brokered MSAL. If a named customer will not buy without "Require app protection policy" Conditional Access, MAUI with Blazor Hybrid is the honest choice. Absent that, its costs (no OTA, no diff control, paid UI vendors, a full C# ramp for a team with no C# projects, roughly 1.2 to 1.8 times the effort) outweigh the auth advantage that Flutter already covers well enough.

**React Native/Expo stays a reasonable second choice** if OTA updates and the TypeScript ecosystem are valued above enterprise auth, but it is the only stack where broker support must be built from scratch.

---

## 2. Scorecard

Scores are 1 (worst) to 5 (best) for Boardhop specifically, as of 2026-09-10.

| Criterion | Weight | React Native / Expo | Flutter | .NET MAUI | Kotlin Multiplatform | Native twins |
|---|---|---|---|---|---|---|
| Entra sign-in with Authenticator broker (v1 decision) | High | 1: build a native module, no maintained package | 4: `msal_auth`, third-party but live | 5: first-party MSAL.NET, MAUI-specific docs (March 2026) | 3: call native SDKs through expect/actual, write the glue | 5 |
| CAE claims-challenge handling (Azure DevOps CAE reached all customers May 2026) | Medium | 2: hand-rolled | 2: not exposed by `msal_auth`, needs a fork or platform channel | 5: `WithClaims` and `cp1` | 3: native SDKs support it, glue needed | 5 |
| Intune App Protection Policy | Low today, decisive if a prospect requires it | 1 | 1 | 4: GA NuGets, but public-store apps need a partner agreement (1 to 3 months) | 1 | 5 |
| Azure DevOps client library | Low | 1: hand-write | 1: hand-write | 2: exists but is a trimming and AOT trap on mobile; hand-write anyway | 1: hand-write | 1: hand-write |
| Kanban drag-and-drop across columns | High | 2: custom on Reanimated | 3: `drag_and_drop_lists` or `appflowy_board`, plus team experience | 4: Syncfusion `SfKanban`, paid | 3: custom on Compose | 4 |
| Rich-text HTML editing of work items | High | 3: TenTap in a WebView | 3: `flutter_quill` plus Delta converters, or `html_editor_enhanced` WebView | 3: Syncfusion or Telerik, paid, fidelity unverified | 3: `compose-rich-editor` | 4 |
| Syntax-highlighted diff with line comments | High | 2: custom, FlashList plus Prism | 2: custom, `re_highlight` plus lists | 2: WebView plus Monaco, C# interop | 3: `compose-code-editor`, KodeView, still custom | 4 |
| HTML and Markdown rendering | Medium | 4 | 5: `flutter_widget_from_html`, `flutter_markdown_plus` | 4 | 3 | 5 |
| Tablet and iPad layouts | Medium | 3: split view alpha, custom breakpoints | 3: SDK rail and breakpoints, adaptive scaffold discontinued | 3: `TwoPaneView`, manual | 3 | 5 |
| iOS text input and accessibility fidelity | Medium | 4: native views | 3: reimplemented, recurring bugs | 4: native views | 3: Compose draws itself on iOS | 5 |
| Push notifications (client side) | Medium | 4: `expo-notifications` | 4: `firebase_messaging` | 3: community plugin | 3 | 5 |
| Over-the-air updates | Medium | 5: EAS Update | 2: Shorebird only | 1: none | 1: none | 1: none |
| Inner loop and tooling | Medium | 5 | 4 | 3 | 3 | 4 |
| Team skill fit (verified) | High | 4: strong TypeScript | 5: two shipped Flutter apps | 1: no C# projects found | 2: one Android project | 2: two languages, two UIs |
| Ecosystem and hiring | Medium | 5 | 4 | 2 | 3 | 4 |
| Effort for the app as scoped (relative) | | 1.0 plus the MSAL module | about 0.9 (auth smaller, editor slightly larger) | 1.2 to 1.8 plus C# ramp | about 1.1 plus auth glue, no team experience | 1.6 to 2.0 |

Weighted reading: Flutter leads on the high-weight rows that matter for launch (broker auth, team fit, boards), ties on the custom-build rows, and loses only on OTA and iOS text fidelity. MAUI leads on enterprise compliance and nothing else. React Native leads on tooling, OTA and ecosystem, and loses the row the v1 plan depends on.

---

## 3. What each stack does to the existing plan

| Decision in document 00 | Under Flutter | Under React Native | Under MAUI |
|---|---|---|---|
| Entra-only launch with broker support | Adopt `msal_auth`; harden the broker path; add a claims-challenge hook (fork or platform channel) before CAE step-up matters | Write the Expo Module over MSAL iOS and Android | `WithBroker()` and `WithClaims()`, done |
| Cloud only | Unchanged | Unchanged | Unchanged |
| Read plus lightweight writes | Unchanged | Unchanged | Unchanged |
| Full rich-text editor in v1 | `flutter_quill` with Delta conversion, or `html_editor_enhanced`; the format-detection and dry-run safeguards stay | TenTap | Syncfusion or Telerik, or a WebView |
| Queued offline writes | `drift` (already used by the team) | MMKV plus TanStack persister | EF Core SQLite |
| Responsive tablet layout | SDK `NavigationRail` and breakpoints | Custom breakpoints | `TwoPaneView` |
| Marketplace extension plus tenant relay | Unaffected; extensions are web code (TypeScript) and the relay is an Azure Function in any language | Unaffected | Unaffected; C# relay shares DTOs |
| Push gateway at kammcs | Unaffected | Unaffected | Unaffected |
| Crash reports only | `sentry_flutter` or `firebase_crashlytics`, scrubbed | Sentry | Sentry |
| iOS and Android together | Unchanged | Unchanged | Unchanged |
| Code on GitHub, test on puremedia | Unchanged; spike scripts stay in Python | Unchanged | Unchanged |

Everything in `research/01` through `research/07` and every spike result remains valid under any stack. The only document that becomes stack-specific is 03, and 08b replaces it for Flutter.

---

## 4. The one question that could change the answer

Does any named prospect require **"Require app protection policy"** Conditional Access for Azure DevOps? That grant needs the Intune App SDK, which Microsoft ships only for native iOS and Android and for MAUI. If the answer is no or unknown, Flutter.

If the answer is yes, Flutter still has a path: **a kammcs-owned Flutter plugin over the native Intune SDKs**, which is how Ionic delivers Intune for Capacitor. What that involves, as of 2026-09-10:

- The plugin owns MSAL sign-in with the broker and then enrolls the same account with `IntuneMAMEnrollmentManager` (iOS) and `MAMEnrollmentManager` (Android). Enrollment satisfies the Conditional Access grant.
- Android: apply the Intune Gradle plugin; it rewrites class references at build time and can rewrite `io.flutter` host classes through its external-library option. Manifest entries overlap with the MSAL broker list.
- iOS: link the IntuneMAM framework, add the `IntuneMAMSettings` dictionary and keychain group. The SDK swizzles UIKit, so share sheet, document picker, screen-capture blocking, PIN and wipe are enforced without app code.
- **Flutter draws its own widgets, so clipboard policy does not apply to Flutter text fields automatically.** Microsoft's "app participation features" list already covers what the SDK cannot enforce alone; a Flutter UI extends it. The app must query policy through the plugin and enforce clipboard, save-as and open-from (`isSaveToAllowedForLocation`, `isOpenFromAllowedForLocation`), notification content (`notificationPolicy`), and file encryption of the offline cache (`isFileEncryptionRequired`) itself.
- Public-store apps must sign the Intune App Partner Agreement (one to three months, legal); admins can target the bundle ID as a custom app meanwhile.
- Effort: three to five weeks for the plugin plus the enforcement points, then Intune SDK updates before every major OS release. Needs an Intune-licensed Conditional Access tenant to test.

That keeps Intune a contained add-on rather than a stack decision. Microsoft has no Flutter SDK and has not answered the Flutter question on its Android SDK repository (issue #190), so this would be unsupported by Microsoft, the same position as Ionic's plugin.

Sources: [Intune App SDK for iOS, app participation features](https://learn.microsoft.com/en-us/intune/intune-service/developer/app-sdk-ios-phase4), [Intune App SDK for Android, get started with MAM](https://learn.microsoft.com/en-us/intune/developer/app-sdk/android-phase-3), [Android SDK issue #190](https://github.com/microsoftconnect/ms-intune-app-sdk-android/issues/190), [Ionic Intune Android installation](https://ionic.io/docs/intune/android-installation), [Appdome Intune MAM](https://www.appdome.com/enterprise-mobile-app-security/uem-mdm-mam/microsoft-intune/).

---

## 5. Flutter-specific spikes before scaffolding

1. **`msal_auth` broker on a Conditional Access tenant.** Register the Entra app with the `msauth.{bundleId}://auth` and Android signature-hash redirect URIs, sign in through Microsoft Authenticator on a real iOS and Android device, and confirm `acquireTokenSilent` survives an app restart. Measure token sizes at the same time.
2. **Claims-challenge path.** Trigger or simulate a CAE challenge (401 with `WWW-Authenticate` claims) and determine whether `msal_auth` needs a fork to pass `claims` into native MSAL. Azure DevOps CAE is live for all customers.
3. **HTML round-trip through the chosen editor.** Take five real work item descriptions from the CloudCover project (tables, nested lists, inline images, mentions), run them through `flutter_quill` Delta conversion and through `html_editor_enhanced`, and diff the output. Pick the editor on the result.
4. **Kanban drag between columns** with `drag_and_drop_lists` and the team's `super_drag_and_drop` experience, on a phone, with haptics and auto-scroll. Confirm 60 fps with 200 cards.
5. **Diff viewer prototype**: `diff_match_patch` plus `re_highlight` plus `super_sliver_list` on a 3,000-line file, with a tap-to-comment gutter.
6. **iOS text field QA**: comment composer and rich-text editor with the keyboard, VoiceOver on, Split View on iPad.

---

## 6. Evidence summary by stack

**React Native / Expo (08c).** No maintained native-MSAL wrapper; `react-native-msal` archived May 2022, every fork disclaimed, `expo-msal` died in 2024. Healthy packages (`react-native-app-auth`, `expo-auth-session`) are browser OAuth with no broker. Microsoft's only artifact is a six-year-old Android proof of concept. Native MSAL SDKs are current (Android 8.4.2, iOS 2.15.0), so a custom module is sound but unprecedented in the open. No Intune SDK.

**Flutter (08b).** `msal_auth` 3.5.3 wraps MSAL Android 8.3 and iOS 2.14.1 with selectable broker, 160/160 pub points, one primary maintainer, broker bugs fixed, no CAE API. No Intune SDK. No Azure DevOps SDK. UI packages cover rendering and editing with known caveats; diff viewer and Kanban polish are custom. No first-party OTA. Quarterly releases, Impeller everywhere, 93 percent satisfaction, 62 percent trust in Google. The Az DevOps competitor proves the feature set is buildable and is dormant since December 2025.

**.NET MAUI (08a).** First-party MSAL.NET broker with a March 2026 MAUI guide; first-party Intune SDK (iOS 21.8.0, Android 12.4.0) with a partner-agreement gate for public apps; the Azure DevOps .NET client libraries are a trimming and AOT liability on mobile; Syncfusion is the only Kanban; no diff control; no OTA since App Center retired in March 2025; MAUI 10 support ends 2027-05-11; adoption roughly a third of React Native's. Effort 1.5 to 1.8 times React Native for XAML, 1.2 to 1.4 for Blazor Hybrid, plus a two- to three-month C# ramp.

**Kotlin Multiplatform (08c).** Compose for iOS stable since May 2025; MSAL glue is thinner than React Native's because the Android half needs no wrapper; a real rich-text and code-editor ecosystem exists. No MSAL wrapper, no team experience, no OTA. Credible, but a bigger bet than Flutter for this team.

**Capacitor (08c).** Two maintained native-MSAL plugins with documented broker configuration, ahead of React Native. WebView UI is the wrong foundation for large diffs and a gesture-driven board.

**Uno, Avalonia, Tauri (08c).** Uno has good MSAL.NET wiring but a thin mobile track record; Avalonia mobile is beta; Tauri cannot use Entra redirect URIs at all.

**Native SwiftUI and Jetpack Compose (08c).** Zero auth or Intune compromise, best text and diff fidelity, 1.6 to 2.0 times the UI effort, two languages.
