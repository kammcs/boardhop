# .NET MAUI as a Foundation for an Azure DevOps Mobile Client — Evaluation

**Document:** 08a
**Date:** 2026-09-10
**Scope:** Is .NET MAUI (in .NET 10 / .NET 11) a better foundation than React Native/Expo for a third-party iOS + Android (phone + tablet) Azure DevOps Services client covering Kanban boards with drag-and-drop, work item forms with HTML/Markdown rich text, PR review with syntax-highlighted diffs and line comments, pipeline runs, and push notifications?
**Assumption (flagged):** The team's existing skills are **TypeScript/web-heavy**, with no deep C#/XAML/mobile-native experience. This assumption materially drives the effort estimates in §8. If the team is actually C#-strong, shift the verdict meaningfully toward MAUI.

---

## Executive summary

**Short answer: No — not as the default foundation, but with one large, specific exception that could flip the decision for you.**

.NET MAUI in 2026 is a genuinely production-capable framework. It is not dying: it shipped GA on 2025-11-11 with .NET 10 (LTS-track), is at .NET 11 RC 1 today with GA due 2026-11-10, has a public monthly servicing cadence, and Microsoft publicly reaffirmed commitment after the May 2025 layoffs. But for *this* app, built by *this* team, MAUI's advantages and disadvantages are lopsided in an unusual way:

**Where MAUI decisively wins — and it is not close:**

1. **Intune App Protection Policy support.** `Microsoft.Intune.Maui.Essentials.iOS` (21.8.0, 2026-08-25) and `.android` (12.4.0, 2026-06-22) are shipping, stable, Microsoft-owned packages, referenced from the official Intune App SDK "Get Started" page, with Microsoft-published MAUI sample apps. React Native has **no** first-party Intune App SDK; the only options are an unmaintained community npm wrapper or hand-rolled native modules. If your target customers use the Conditional Access grant **"Require app protection policy"**, this is close to a binary gate — and it is the single strongest argument for MAUI in this entire evaluation.
2. **Brokered Entra auth (Microsoft Authenticator / Company Portal).** MSAL.NET's `WithBroker()` on iOS and Android is first-party, and as of March 2026 there is a *dedicated, current, MAUI-specific* Microsoft Learn article covering redirect URIs, `WithParentActivityOrWindow`, keychain access groups, and Android package-visibility queries. React Native has no first-party MSAL binding at all.
3. **Continuous Access Evaluation.** Azure DevOps CAE rolled out to all customers by May 2026; MSAL.NET's `WithClaims()` + `cp1` client capability is the reference implementation path.

**Where MAUI clearly loses:**

1. **Rich text and diff rendering.** There is no credible native MAUI control for syntax-highlighted code diffs. You will end up embedding Monaco/Prism/Shiki in a `WebView`/`HybridWebView` — i.e. you write the web code anyway, but now you also pay the C#↔JS interop tax and lose the React ecosystem around it. Rich-text HTML editing means paying Syncfusion or Telerik, or again a WebView.
2. **No OTA updates.** App Center and CodePush were retired 2025-03-31 with no successor. There is no .NET MAUI equivalent to EAS Update. For a third-party client tracking a fast-moving Azure DevOps REST surface, losing sub-24-hour hotfixes is a real operational cost.
3. **Skill fit.** A TypeScript/web team pays a full C# + XAML (or Razor) + MSBuild + platform-bindings learning curve. Nothing in MAUI reuses their existing skills except via Blazor Hybrid — and Blazor Hybrid is Razor/C#, *not* TypeScript, so the reuse is HTML/CSS knowledge only, not code.
4. **Ecosystem velocity.** ~3.4% developer adoption vs ~9% for React Native (secondary source, see §7), a much thinner package ecosystem, and a smaller hiring pool.
5. **Azure DevOps .NET client libraries are a trap on mobile.** They are `netstandard2.0`, documented for "Windows apps and services", and depend on `Newtonsoft.Json` + `Microsoft.AspNet.WebApi.Client` — a reflection-heavy stack with a long, well-documented history of breaking under iOS trimming/AOT. The "free typed models" benefit is real but is not free on mobile.

**Recommended decision shape:** Stay on React Native/Expo **unless** "Require app protection policy" Conditional Access is a hard requirement from named prospects. If it is, the honest choice is between (a) MAUI, and (b) React Native with hand-written Intune MAM native modules — and (b) is genuinely risky, unsupported, and Microsoft has repeatedly declined to support it. A third path worth costing: **MAUI Blazor Hybrid**, which gets you the Intune/MSAL wins while letting the diff viewer, Markdown renderer, and rich-text editor be actual web components — but it does not get you TypeScript.

---

## Scorecard

| Criterion | MAUI status (Sept 2026) | Maturity 1–5 | Notes |
|---|---|---|---|
| **Brokered Entra auth (MSAL.NET, iOS+Android)** | First-party, documented, current | **5** | Dedicated MAUI Learn article updated 2026-03; `WithBroker()`, `msauth.{bundle}://auth`, keychain groups all covered. RN has no first-party equivalent. |
| **Azure DevOps resource scopes + CAE** | Fully supported | **5** | `499b84ac-…/vso.work` etc. work as normal MSAL scopes; `WithClaims()` + `cp1` for CAE. |
| **Intune App Protection Policy (APP/MAM)** | GA, Microsoft-owned NuGets, MAUI samples | **4** | iOS 21.8.0 / Android 12.4.0. Deducted 1 point for history of version lag (see §2) and thin adoption (~39K/29K lifetime downloads). Still the killer feature. |
| **Azure DevOps .NET client libraries on mobile** | Works in principle, unvalidated on iOS/Android | **2** | `netstandard2.0` so it *resolves*; Newtonsoft + WebApi.Client reflection is a known trimming/AOT hazard. **Requires a spike before committing.** |
| **Kanban drag-and-drop across columns** | Syncfusion `SfKanban`, production-ready since 2025 Vol 1 | **4** | Only credible option. Telerik and DevExpress have no MAUI Kanban. Licensing gate applies. |
| **Rich-text HTML editor** | Syncfusion (2025 Vol 3+), Telerik RichTextEditor | **3** | Both output HTML; neither is validated against Azure DevOps' specific HTML field dialect. Paid. WebView fallback always available. |
| **Syntax-highlighted code / diff viewer** | No native control; WebView + Monaco | **2** | Community `maui-monaco` wrappers are small/low-maturity. You are writing web code regardless. |
| **Markdown rendering** | Several native renderers + Syncfusion viewer | **4** | `Indiko.Maui.Controls.Markdown`, Shiny Markdown, `Microsoft.Maui.Graphics.Text.Markdig`. Native, no WebView needed. |
| **Tablet / iPad adaptive layouts** | `TwoPaneView`, `FlyoutPage`, Shell | **3** | Workable but manual; `TwoPaneView` lives in the separate `Microsoft.Maui.Controls.Foldable` package; documented iPadOS orientation caveats. |
| **Virtualized lists (thousands of diff lines)** | `CollectionView` w/ new iOS handlers default in .NET 10 | **3** | Materially better than .NET 8, but heavy-template scenarios still push people to Syncfusion `SfListView`. For a diff viewer, a WebView with its own virtualization is likely the pragmatic answer anyway. |
| **Secure storage + SQLite/offline** | `SecureStorage` + `sqlite-net`/EF Core SQLite | **4** | Solid. Strings-only; MSAL manages its own cache. No documented MAUI 2KB limit (see §4g). |
| **Push notifications (FCM/APNs)** | Community plugins; no first-party MAUI push API | **3** | `Plugin.FirebasePushNotifications` 3.2.11 is the de-facto choice. Azure Notification Hubs has **no MAUI client SDK**. |
| **Hot reload / inner loop** | Substantially improved in .NET 11 | **3→4** | XAML Incremental Hot Reload (.NET 11 P7), `dotnet watch` for Android and iOS (.NET 11 P4). Historically the #1 complaint; genuinely better now but still behind Metro/Fast Refresh. |
| **OTA updates** | **None** | **1** | CodePush/App Center retired 2025-03-31. No MAUI equivalent to EAS Update. |
| **App size / startup** | NativeAOT on iOS only; CoreCLR default in .NET 11 | **3** | NativeAOT iOS: ~2x faster startup, >2x smaller. **NativeAOT not supported on Android.** |
| **CI/CD** | Standard; macOS runners mandatory for iOS | **3** | Same constraint as RN. GitHub Actions macOS ≈ $0.062/min with a 10x minute multiplier. |
| **Blazor Hybrid as UI layer** | Mature, viable, with a WebView perf tax | **4** | Good escape hatch for diffs/rich text. Razor/C#, not TypeScript. |
| **Ecosystem health / hiring** | Alive, supported, but small and slower | **3** | ~3.4% adoption vs RN ~9%. Post-layoff commitment publicly reaffirmed. |
| **Team skill fit (TS/web team)** | Poor | **1** | Full C#/XAML/MSBuild ramp. Blazor Hybrid softens but does not solve this. |

---

## 1. Authentication — MSAL.NET on MAUI

### Is brokered auth supported from MAUI on iOS and Android?

**Yes, and it is first-party and currently documented.** Microsoft Learn's *Authenticate users with MSAL.NET* article for .NET MAUI (`ms.date: 2026-03-17`, page updated `2026-03-20`, monikers through `net-maui-11.0`) is a purpose-written MAUI guide, not a Xamarin retread. It explicitly covers:

- **Packages:** `Microsoft.Identity.Client` and `Microsoft.Identity.Client.Broker` (`Version="4.*"`). Latest MSAL.NET at time of research: **4.88.0**.
  > "`Microsoft.Identity.Client.Broker` is required for broker support (Microsoft Authenticator, Company Portal, and Windows WAM)."
- **Redirect URIs:**
  - Android: `msal{ClientId}://auth`
  - iOS/Mac Catalyst: `msauth.{BundleId}://auth`
  - Windows (broker/WAM): `ms-appx-web://microsoft.aad.brokerplugin/{ClientId}`
- **`WithBroker()`** applied under `#if ANDROID || IOS || MACCATALYST`, and `WithBroker(new BrokerOptions(BrokerOptions.OperatingSystems.Windows))` on Windows.
- **`WithIosKeychainSecurityGroup("com.microsoft.adalcache")`**, with the matching `keychain-access-groups` entry `$(AppIdentifierPrefix)com.microsoft.adalcache` in **`Entitlements.plist`** (the docs explicitly warn: not `Info.plist`).
- **iOS `LSApplicationQueriesSchemes`:** `msauthv2`, `msauthv3` — required for MSAL to *detect* broker availability.
- **Android package-visibility `<queries>`** for `com.azure.authenticator`, `com.microsoft.windowsintune.companyportal`, `com.microsoft.workaccount` — mandatory on Android 11+.
- **Android `MsalActivity : BrowserTabActivity`** with `[IntentFilter]` on `DataScheme = "msal{ClientId}"`, plus `OnActivityResult` forwarding to `AuthenticationContinuationHelper.SetAuthenticationContinuationEventArgs`.
- **iOS `AppDelegate.OpenUrl`** override forwarding broker responses via `AuthenticationContinuationHelper.SetBrokerContinuationEventArgs`, explicitly noting it must be dispatched to a background thread.
- **`WithParentActivityOrWindow`**, with an unusually blunt warning:
  > "On Android, always pass `.WithParentActivityOrWindow(Platform.CurrentActivity)` to `AcquireTokenInteractive`. Omitting this causes a crash at runtime because MSAL cannot find a parent window to host the sign-in UI."

The doc also includes a `DelegatingHandler` bearer-token pattern and a Blazor Hybrid `AuthenticationStateProvider` — both directly reusable for this app.

### Maturity and documentation quality in 2026

**High (5/5).** Official MAUI support was announced in `Microsoft.Identity.Client` 4.47.0. There is a Microsoft-maintained sample (`Azure-Samples/ms-identity-dotnetcore-maui`) and Microsoft Learn External-ID MAUI tutorials. The March 2026 article closed the last significant documentation gap (tracked as `dotnet/docs-maui#3228`).

**Contrast with React Native:** there is no first-party MSAL binding for React Native. RN apps use `react-native-app-auth` / community MSAL wrappers, which do not do brokered auth and therefore cannot satisfy device-compliance or app-based Conditional Access cleanly. This is the *root* of MAUI's enterprise-auth advantage — and it compounds with §2.

### Known pain points

| Pain point | Detail |
|---|---|
| **Historical Android security advisory** | `GHSA-x674-v45j-fwxw`: MSAL.NET on Xamarin Android / .NET Android (MAUI) versions **4.48.0–4.60.3** (excluding 4.59.1 and 4.60.3) were susceptible to HTML/JS injection in embedded web views or local DoS due to incorrect activity export configuration. **Fixed in 4.60.3.** Long resolved, but it illustrates that the Android activity/intent surface is the fragile part. |
| **`WithParentActivityOrWindow` omission** | The single most common MAUI+MSAL crash. Requires `Platform.Init(this, savedInstanceState)` in `MainActivity.OnCreate`. |
| **iOS keychain access groups** | Must match `WithIosKeychainSecurityGroup` *exactly* and live in `Entitlements.plist`; the provisioning profile must include the group. Mismatches fail silently or as opaque keychain errors — historically the #1 iOS broker support burden. |
| **`Microsoft.Identity.Client.Broker` vs built-in** | On **iOS/Android**, broker support is built into `Microsoft.Identity.Client` itself — `WithBroker()` works without the extra package. `Microsoft.Identity.Client.Broker` is required for **Windows WAM** (and macOS). The Learn doc references both packages up front, which reads as slightly over-prescriptive for a mobile-only app. **Practical guidance:** add `Microsoft.Identity.Client.Broker` only if/when you ship Windows. |
| **Android broker install-state variance** | Behaviour differs across Authenticator-only, Company Portal-only, both-installed, and neither-installed devices, plus work-profile scenarios. This is a *testing matrix* cost, not a MAUI defect — but budget for real-device testing across at least 4 configurations. |
| **Unique client ID per platform** | The Intune docs require: "The Microsoft Entra Client ID for your app must be unique across iOS and Android platforms" for app-based Conditional Access. Easy to get wrong; forces two app registrations. |

### Azure DevOps scopes and CAE

**Scopes: fully supported.** Azure DevOps' resource App ID is `499b84ac-1321-427f-aa17-267ca6975798`. MSAL.NET public clients request these as ordinary scopes:

```
499b84ac-1321-427f-aa17-267ca6975798/vso.work
499b84ac-1321-427f-aa17-267ca6975798/vso.code_full
499b84ac-1321-427f-aa17-267ca6975798/user_impersonation
499b84ac-1321-427f-aa17-267ca6975798/.default
```

Nothing MAUI-specific applies; this is standard MSAL scope handling. (`/.default` grants everything statically configured on the app registration; `user_impersonation` plus `AzureAdAndPersonalMicrosoftAccount` authority is the pattern used to support MSA identities alongside Entra.)

**CAE: supported, and Azure DevOps now requires you to handle it.**

- Azure DevOps CAE was announced on the Azure DevOps blog **2025-08-12**.
- Update on **2026-04-17**: *"Continuous Access Evaluation (CAE) rollouts are in progress. It is now available to some customers, and will be rolled out to all customers by May 2026."* — i.e. **CAE is live in production for your users today.**
- Developer obligation, per the blog: on `401 Unauthorized`, *"extract the challenge, fetch a new token, and retry the request."*
- MSAL.NET path: declare client capability **`cp1`** on the `PublicClientApplicationBuilder`, then pass the challenge via **`WithClaims(claimChallenge)`** on `AcquireTokenSilent`, falling back to `AcquireTokenInteractive().WithClaims(claimChallenge)` on `MsalUiRequiredException`.
- The .NET client libraries surface claims challenges as of **20.259.0** (`-preview`). Python/Go support followed later.

**Implication for React Native:** CAE claims-challenge handling is *implementable* in RN — it is just a WWW-Authenticate header parse and a re-auth — but you will hand-roll what MSAL.NET gives you as a one-line builder call. Moderate, not decisive.

---

## 2. Intune App Protection Policies — the real differentiator

### Is there an Intune App SDK for MAUI in 2026?

**Yes, and it is GA and current.** The official Intune App SDK "Get Started" page (updated `2026-07-01`) directs MAUI developers explicitly:

> "If your app builds with .NET Multi-platform App UI (.NET MAUI), use this SDK variant: [Intune App SDK for .NET MAUI - Android], [Intune App SDK for .NET MAUI - iOS]"

| Package | Latest version | Published | Target frameworks | Lifetime downloads |
|---|---|---|---|---|
| `Microsoft.Intune.Maui.Essentials.iOS` | **21.8.0** (stable) | **2026-08-25** | `net9.0-ios26.0`, `net10.0-ios` | ~38.7K |
| `Microsoft.Intune.Maui.Essentials.android` | **12.4.0** (stable) | **2026-06-22** | `net9.0-android35.0`, `net10.0-android36.0`, `netstandard2.0` | ~29.1K |

The iOS package description notes it wraps **Intune App SDK for iOS 21.8.0** and **MSAL for iOS 2.15.0**. Recent iOS release cadence has been roughly every 6–10 weeks (21.2.0 → 2025-11-04, 21.4.0 → 2026-01-13, 21.5.0/21.5.1 → 2026-03, 21.6.0 → 2026-05-08, 21.7.1 → 2026-07-16, 21.8.0 → 2026-08-25). Android is slower and lumpier (10.0.0 → 2023-11-27, 11.5.1 → 2025-10-06, 12.4.0 → 2026-06-22).

Microsoft publishes MAUI sample apps: `microsoftconnect/sample-intune-maui-ios` (contains `IntuneMAMiOSMauiSample`) and an equivalent Android sample.

**GA date:** the Android package left beta with `10.0.0` on **2023-11-27**; both packages have shipped stable versions continuously since. There is no single "GA announcement" moment — treat it as GA since late 2023, with the Xamarin bindings' end of support on **2024-05-01** being the forcing function that moved everyone to the MAUI packages.

### The version-lag risk (real, and worth pricing in)

`dotnet/maui#31860`, opened **2025-10-03**, titled *"[.NET MAUI] Intune SDK (Microsoft.Intune.Maui.Essentials.Android) not compatible with .NET 9 – critical blocker for MAUI apps"*, documented that the Android package lagged the framework while Microsoft simultaneously mandated that apps update to the latest Intune SDK by **2025-12-15** or be blocked from launching. The issue is now **closed**, and the current 12.4.0 package targets `net10.0-android36.0`, so the gap is resolved.

**But the pattern is the risk.** The Intune SDK team ships on the Intune service's cadence, not .NET's. Two structural obligations follow, straight from the Intune docs:

> "Plan to take mandatory Intune App SDK updates prior to every major OS release… If you do not update to the latest version prior to a major OS release, you may run the risk of encountering a breaking change and/or being unable to apply app protection policies to your app."

Budget for a **standing quarterly maintenance obligation** on the Intune SDK, independent of your own release cadence, plus the possibility of being pinned to an older .NET TFM for a few months after each November .NET release.

### The public-app-store registration requirement (often missed)

This is the part most evaluations skip, and it is a **business process, not a code task**. From the Intune "Get Started" page:

- **Internal LOB apps:** no registration needed. Intune detects the SDK and admins can apply policy.
- **Apps released to the Apple App Store or Google Play — i.e. yours:** *"You **must** first register your app with Microsoft Intune and agree to the registration terms."* The process is: complete the **Microsoft Intune App Partner Questionnaire** (`aka.ms/IntuneAppPartner`) → Microsoft contacts you → sign the **Microsoft Intune App Partner Agreement** → your app is listed under **Partner productivity apps** and on the Microsoft Intune Partners page → *"your app's deep link will be added to the next monthly Intune Service update"* (e.g. finish in July → live mid-August).

**Important mitigation:** admins are *not* blocked in the meantime. The same docs state:

> "If your app has integrated the Intune SDK, but isn't listed in the list of targetable apps, you can specify the app's bundle ID (iOS) or package name (Android) in the text box when selecting **Custom Apps**."

So a customer's IT admin can target your app by bundle ID / package name from day one; partner registration buys discoverability, the badge, and a smoother admin experience. **Plan for ~1–3 months of lead time** on the partner agreement, and note it requires a legal signature.

Additional requirements for app-based Conditional Access to work, per the same page:

- App is built with MSAL and **enabled for Microsoft Entra broker authentication** (this is why §1 and §2 are the same argument).
- The **Entra Client ID must be unique across iOS and Android**.
- If using your own Entra app registration (not the Intune SDK default client ID), you must grant it the delegated permission **`DeviceManagementManagedApps.ReadWrite`** on the *Microsoft Mobile Application Management* API.

### Can React Native satisfy "Require app protection policy"?

**Not in a supported way.** Confirmed:

- Microsoft ships **no** official Intune App SDK for React Native. Long-standing requests exist on the iOS SDK repo (`ms-intune-app-sdk-ios` issues **#21** and **#218**) and remain unfulfilled.
- The community options are `react-native-ms-intune-mam` (npm, community-maintained) and manual native-module integration of the native iOS/Android Intune SDKs.
- Third-party no-code wrapping services (e.g. Appdome) exist as a commercial alternative but add cost, a build-pipeline dependency, and a vendor in your release path.

The Conditional Access docs confirm the grant works for *"additional third-party public apps that have integrated the Intune SDK"* and *"line-of-business apps that have integrated the Intune SDK (or have been wrapped)"* — so the gate is **SDK integration**, not framework. RN *can* theoretically pass it via native modules; the question is whether you want to own an unsupported native integration of a security-critical SDK that ships breaking changes ahead of every major OS release.

**Verdict on §2:** This is the strongest, least-arguable case for MAUI in this evaluation. If enterprise customers demand APP-based Conditional Access, MAUI turns a high-risk unsupported integration into a supported NuGet reference.

---

## 3. Azure DevOps .NET client libraries on MAUI

### Current state

| Package | Latest stable | Date | Latest preview | Date |
|---|---|---|---|---|
| `Microsoft.TeamFoundationServer.Client` | **20.256.2** | **2026-03-11** | **20.277.0-preview** | **2026-08-11** |
| `Microsoft.VisualStudio.Services.Client` | 20.256.2 (pinned `=`) | 2026-03-11 | — | — |

- **Target frameworks:** `.NET Standard 2.0` and `.NET Framework 4.7.2`.
- **Dependencies:** `Microsoft.AspNet.WebApi.Client` (≥ 5.2.7), `Microsoft.VisualStudio.Services.Client` (`= 20.256.2`), `Newtonsoft.Json` (≥ 13.0.3), `System.ComponentModel.Annotations` (≥ 5.0.0).
- **Downloads:** ~42.3M lifetime; ~171K/day. Actively maintained (monthly-ish preview drops).
- **Maintenance status:** actively serviced. Notably, the CAE claims-challenge support landed in **20.259.0**, which is *newer than the current stable* — so CAE-aware code needs a preview package today. **Flag this.**

### Do they work on MAUI (iOS/Android)?

**Officially: unstated, and the docs point the other way.** The Learn page is explicit about audience:

> "Client libraries are available for .NET developers who build **Windows apps and services** that integrate with Azure DevOps."

and separately:

> "Authentication paths that produce an interactive dialog aren't available in the .NET Standard version of the .NET client libraries."

`netstandard2.0` means they will **resolve and reference** from a `net10.0-ios` / `net10.0-android` MAUI project. There is no MAUI-targeted testing, sample, or support statement. **Mark as: plausible but unverified — requires a spike.**

**The specific technical hazards, in priority order:**

1. **Newtonsoft.Json + trimming/AOT on iOS.** This is the big one, and it is extremely well documented across `dotnet/maui` issues (#13033, #8122, #24491, #27374) and `JamesNK/Newtonsoft.Json#2912`. The failure mode is nasty: **works in Debug, fails in Release**, typically as `JsonSerializationException` or `Attempting to JIT compile method … while running in aot-only mode`. Community guidance is unambiguous: *"Newtonsoft.Json shouldn't be used with iOS projects because it requires reflection and metadata"*; use `System.Text.Json` with source generation. The ADO client libraries give you no choice — Newtonsoft is baked in.
   - **Mitigations:** disable trimming (`<PublishTrimmed>false</PublishTrimmed>`) and avoid full AOT — at the cost of app size and startup. Or aggressively preserve types via a linker XML / `[DynamicDependency]`. Both are ongoing maintenance burdens.
   - **NativeAOT on iOS is effectively off the table** if you take this dependency.
2. **`Microsoft.AspNet.WebApi.Client` (`System.Net.Http.Formatting`).** A legacy ASP.NET-era formatter stack, reflection-heavy, and the historical source of the classic `Method not found: get_SerializerSettings` binding failure when Newtonsoft versions drift. It is not designed for or tested on mobile.
3. **`VssConnection` design.** The library assumes a long-lived connection object and a desktop/service HTTP stack. Injecting a bearer token works (`new VssBasicCredential(string.Empty, accessToken)` per the docs' Entra example), but wiring in your own `HttpMessageHandler` for token refresh, CAE claims-challenge retry, and MAUI-friendly HTTP (`NSUrlSessionHandler` on iOS) is fiddly.
4. **Binary size.** The full `TeamFoundationServer.Client` surface pulls in a large set of assemblies (`Build2.WebApi`, `Core.WebApi`, `WorkItemTracking.Process.WebApi`, `SourceControl.WebApi`, `TestManagement.WebApi`, …). You need work items, Git/PRs, boards, and builds — a meaningful but not total slice. With trimming disabled (see #1), you ship the lot.

### Should you use them instead of hand-written REST?

**Recommendation: hand-written REST with generated or hand-written typed models, using `System.Text.Json` source generation.**

| | ADO client libraries | Hand-written REST |
|---|---|---|
| Typed models for work items, PRs, boards, builds | ✅ Free, and correct | ❌ You write/generate them |
| API-version handling, URL construction | ✅ Handled | ❌ You handle it |
| Trimming / NativeAOT on iOS | ❌ Hazardous | ✅ Clean with STJ source-gen |
| App size | ❌ Large, un-trimmable | ✅ Minimal |
| CAE claims challenge | ✅ (20.259.0+, preview only today) | ✅ Trivial to implement |
| Control over caching, ETags, retry, offline | ❌ Fights you | ✅ Full control |
| Parity with an existing RN implementation | ❌ Divergent | ✅ Reuses your REST knowledge |

The typed-model benefit is genuine — Azure DevOps' work-item and PR payloads are gnarly — but you can capture most of it by generating C# models from the published REST API surface, or simply porting the TypeScript types you already have. **A middle path worth considering:** reference the client libraries *at design time only* to crib the model shapes, then ship hand-written STJ models.

**Also note:** this analysis changes the "MAUI gives you free Microsoft client libraries" talking point substantially. On mobile, that advantage is roughly **neutral-to-negative**, not a win. Do not let it carry weight in the decision.

---

## 4. UI building blocks

### (a) Kanban drag-and-drop across columns

**Syncfusion `SfKanban` is the only credible option.**

- Package: `Syncfusion.Maui.Kanban`. Requires **.NET 9 SDK or later**; VS 2022 17.12+, VS Code, or Rider 2024.3+.
- **Introduced in preview: Essential Studio 2024 Volume 3. Marked production-ready: Essential Studio 2025 Volume 1** (announced ~2025-04-08).
- Features relevant here: drag-and-drop between and within columns, `PlaceholderStyle` on `KanbanColumn` for the drop target, a `DragOver` event when a card is dragged to a new index, **workflows** that constrain which column-to-column transitions are legal, and the ability to disable drag/drop per column.
  - The workflow/transition-restriction feature maps *directly* onto Azure DevOps work-item state transition rules. This is a real, concrete fit.
- **Not available from Telerik** (no MAUI Kanban found) or **DevExpress** (their free MAUI suite is DataGrid, Scheduler, Charts, TabView, Editors, Menu — no Kanban).
- **Community:** nothing production-grade. MAUI's built-in `DragGestureRecognizer`/`DropGestureRecognizer` can implement Kanban by hand, but multi-column reordering with autoscroll, placeholder animation, and touch-precision on phones is weeks of work with a poor ceiling.

**vs React Native:** RN has multiple mature Kanban/DnD options (`react-native-reanimated` + `react-native-gesture-handler`, `react-native-draggable-flatlist`, and several board libraries), all free, all with far more real-world touch-tuning. **RN wins on cost and options; MAUI wins on "one vendor, one support contract" if you're buying Syncfusion anyway.**

### (b) Rich-text HTML editor

Azure DevOps work item long-text fields (`System.Description`, `Repro Steps`, etc.) are **HTML**, while PR/work-item *comments* and wiki are **Markdown**. You need both.

| Option | Status | Notes |
|---|---|---|
| **Syncfusion `SfRichTextEditor` for MAUI** | Introduced **Essential Studio 2025 Volume 3**; 2026 Vol 1 added pasting multiple images plus audio/video | Bold/italic/underline/strikethrough, font family/size, text + background colour, lists, indentation, alignment, hyperlinks, images, tables. Newest of the three — least field-hardened. |
| **Telerik `RichTextEditor` for MAUI** | Shipping, mature | Explicitly *"outputs the modified content as standard HTML"* — the right contract for ADO fields. Part of the 70+ control suite. |
| **DevExpress** | ❌ | No rich text editor in the free MAUI suite. |
| **WebView + Quill/TipTap/ProseMirror** | Always available | Exactly what an RN app would do — and then you've written the web code anyway. |

**Critical unverified risk:** neither Syncfusion nor Telerik documents fidelity against Azure DevOps' *specific* HTML dialect. ADO round-trips a constrained HTML subset and is notorious for mangling foreign markup (nested lists, `<img>` with attachment URLs, tables, pasted Word content). **Mark as unverified: you must spike round-tripping real ADO work-item HTML through whichever editor you choose, and check that a save-without-edit is a no-op diff.** This is a top-3 technical risk for the whole app on either framework.

### (c) Syntax-highlighted code / diff viewer

**There is no native MAUI control for this. None of Syncfusion, Telerik, or DevExpress ships a code editor or diff viewer for MAUI.**

Your options:

1. **`WebView` / `HybridWebView` + Monaco.** Community wrappers exist: `flynk/maui-monaco` (claims a strongly-typed C# API, diff support, diagnostics, custom themes) and `lk-code/maui.monaco-editor`. Both are small single-maintainer projects — **treat as reference implementations, not dependencies**. Monaco on mobile is also heavy; many teams prefer a lighter path.
2. **`WebView` + Prism.js / Shiki / highlight.js + a hand-rolled diff DOM.** More work, far lighter, much better mobile touch behaviour, and gives you full control over the two-pane vs unified diff toggle and line-comment gutter. **This is the recommended approach on either framework.**
3. **Native rendering with `Label`/`FormattedString` spans + a C# highlighter.** Possible (ColorCode-Universal, TextMateSharp) but you will fight per-line performance, horizontal scrolling, and text selection.

.NET 10 helps here more than you'd expect: **`HybridWebView` gained `WebResourceRequested` interception** (serve diff payloads and highlighter assets from local streams without a file server), an `InvokeJavaScriptAsync` overload for void-returning JS, `WebViewInitializing`/`WebViewInitialized` events, and JS exceptions now re-thrown as .NET exceptions. .NET 11 P6 adds `SetInvokeJavaScriptTarget<T>(target, JsonSerializerContext)` so JS→.NET calls use **source-generated JSON**, making the interop bridge NativeAOT- and full-trim-compatible. That is a genuinely good interop story.

**But note the strategic consequence:** the hardest, highest-value screen in this app (PR diff review with line comments) is a **web view on both frameworks**. MAUI's advantage evaporates here; RN's advantage is that the surrounding code is the same language as the WebView contents.

### (d) Markdown rendering

**Good coverage, all native (no WebView required):**

| Library | Notes |
|---|---|
| `Indiko.Maui.Controls.Markdown` (1.5.0) | Renders to native MAUI views — `Label`, `Grid`, `Image`, `BoxView`. Has a theming system as of 1.5.0. Pins Markdig to `[1.3.2, 2.0.0)`. |
| **Shiny.NET Markdown** | Read-only `MarkdownView` **plus a full `MarkdownEditor`** with formatting toolbar and live preview. Markdig-based; tables and task lists supported. **The editor is notable** — it directly addresses PR/work-item comment composition. |
| `Plugin.Maui.MarkdownView` (1.0.5) | Builds UI from Markdown files. |
| `Microsoft.Maui.Graphics.Text.Markdig` (10.0.60) | Microsoft-owned; parse/render via `Microsoft.Maui.Graphics`. Low-level. |
| Syncfusion Markdown Viewer for MAUI | Headers, lists, images, tables, code blocks. |

**Gap:** ADO Markdown has extensions (`@mentions`, `#work-item` links, `[[wiki links]]`, `:::mermaid`, attachment references, `[ ]` task lists with ADO semantics). None of these renderers know about them; you will write Markdig extensions or post-process. Same cost on RN with `react-native-markdown-display`. **Neutral.**

### (e) Tablet / iPad adaptive layouts

- **`TwoPaneView`** is the split-view primitive — but it ships in the **separate `Microsoft.Maui.Controls.Foldable` NuGet package**, not the core framework, and originated as a Surface Duo dual-screen control. It works on tablets as a responsive split view (side-by-side or stacked, proportional or min-width-driven sizing).
- **`FlyoutPage`** and **Shell** provide master/detail and navigation structure.
- **Documented iPadOS caveat:** *"On iPadOS, the orientation state is not triggered on device rotation, because iPad supports multitasking through split view and slideover, which means the orientation of the device may not reflect the orientation of the window."* You must drive adaptive layout off **window size**, not device orientation. Standard practice, but a common MAUI bug source.
- **.NET 10 SafeArea overhaul** is a real quality-of-life win: `SafeAreaEdges` (`None` / `SoftInput` / `Container` / `Default` / `All`) on `Layout`, `ContentView`, `ContentPage`, `Border`, `ScrollView`, plus iOS safe-area fixes. This class of bug (extra bottom padding in `ScrollView`, keyboard overlap) was a persistent MAUI complaint.
- **.NET 10 secondary toolbar items** on iOS/macOS map `Order="Secondary"` into a native iOS 13+ pull-down ellipsis menu — useful for work-item action overflow.

**Assessment: 3/5.** Everything you need exists; none of it is as ergonomic as CSS flexbox + `useWindowDimensions` in RN, and `TwoPaneView` living outside the box is a smell.

### (f) High-performance virtualized lists (thousands of diff lines)

- **`CollectionView`** is the supported virtualized list. In **.NET 10, the optional iOS/Mac Catalyst handlers from .NET 9 became the default** ("CV2"), with an opt-out available in `MauiProgram.cs`. This is a genuine stability/perf improvement.
- **`ListView` and `TableView` are deprecated in .NET 10** (along with `EntryCell`, `ImageCell`, `SwitchCell`, `TextCell`, `ViewCell`). Do not use them.
- **History matters:** virtualization was **completely broken** in `8.0.0-rc.2.9530` (`dotnet/maui#18639` — `CollectionView` loaded every item from `ItemsSource` regardless of viewport), and Android scrolling perf was a long-running community grievance (`dotnet/maui` discussion #18027). Fixed, but the scar tissue is why third-party vendors still market against it.
- **Practical guidance that still applies:** put `CollectionView` in a `Grid` with a `*` row; **never** nest it in a `StackLayout` or `ScrollView` (breaks virtualization); keep item templates shallow. For heavy templates plus continuous paging, Syncfusion `SfListView` still outperforms via load-on-demand.
- **For the diff viewer specifically:** if you go the WebView route (recommended, §4c), this is moot — you virtualize in JS. **This actually removes MAUI's biggest list-perf risk from the critical path.**

### (g) Secure storage and offline SQLite

**`SecureStorage`:**
- API: `SecureStorage.Default`, **strings only** (encode other types as JSON).
- **Android:** `EncryptedSharedPreferences`; on API 23+ an AES key from the Android KeyStore with `AES/GCM/NoPadding`.
- **iOS:** Keychain.
- **The 2KB limit in the question is an Expo `SecureStore` constraint, not a MAUI one.** Expo SecureStore documents a 2048-byte per-value limit; **no equivalent documented limit was found for MAUI `SecureStorage`** in Microsoft's docs. **Mark as unverified — but treat as a non-issue in practice**, because you should not be storing tokens there anyway: **MSAL.NET manages its own encrypted token cache** (Keychain on iOS with your access group; KeyStore-backed on Android). Use `SecureStorage` for small app secrets and preferences only.
- **Known operational hazard:** data corruption after backup/restore on Android and after iOS device migration. Always handle a decryption failure by clearing and forcing re-auth rather than crashing.

**SQLite / offline:**
- `sqlite-net-pcl` on `SQLitePCLRaw` is the standard, mature choice; **EF Core with the SQLite provider** also works on MAUI (and gives you migrations) at a startup-time and size cost.
- Watch for the common "database not loading on iOS/Android but works on Windows" class of bug — almost always a path issue (`FileSystem.AppDataDirectory`) or a missing `SQLitePCLRaw.bundle_*` provider init.
- **Encryption at rest:** SQLCipher via `SQLitePCLRaw.bundle_e_sqlcipher` if APP policy or customer requirements demand it. **This is required in practice if you integrate Intune MAM** — App Protection Policies can require app data encryption, and your SQLite cache of work items and diffs is app data. Budget for it.

**vs RN:** `expo-sqlite` / `op-sqlite` are equally mature; `expo-secure-store` has the 2KB limit MAUI apparently lacks. **Roughly a wash, slight edge MAUI.**

### Licensing costs summary

| Vendor | MAUI cost | Terms |
|---|---|---|
| **Syncfusion** | **Community License: free** if annual gross revenue **< $1M USD**, **≤ 5 developers**, **≤ 10 total employees**, and the entity has **never received > $3M USD** in outside capital (PE/VC). Otherwise: **~$959/developer/year** for individual SDKs (Grid, Chart, Scheduler, Gantt, Diagram, **Rich Text Editor**); Document SDK ~$1,199; PDF Viewer ~$599. Essential Studio team licences are **per developer, minimum 5 developers**, annual/temporal. | Stated Community License value ~$12,475 for 1,600+ components. **The community thresholds are strict and cumulative — the $3M lifetime-outside-capital clause disqualifies most funded startups permanently.** Verify eligibility with counsel before building on it. |
| **Telerik (UI for .NET MAUI)** | From **~$849/developer/year**; also in DevCraft Complete/Ultimate bundles. | Includes `RichTextEditor`. **No Kanban for MAUI found.** |
| **DevExpress (.NET MAUI)** | **Free of charge**, usable indefinitely, free updates. | **No technical support** unless you own a Universal Subscription. Suite is DataGrid, Scheduler, Charts, TabView, Editors, Menu — **no Kanban, no rich text, no diff viewer**, so it does not cover your needs. |

**Bottom line on licensing:** if you fail Syncfusion's Community thresholds, **realistic third-party control spend is roughly $1,000–$5,000/year** (Syncfusion for Kanban + Rich Text + possibly SfListView, on a 5-developer minimum team licence, or Telerik at $849/dev/yr without a Kanban). React Native's equivalent components are free and open-source. **Net: MAUI carries a recurring licence cost that RN does not — call it $2–5K/year, plus vendor lock-in on your two hardest UI surfaces.**

---

## 5. Push notifications

### First-party MAUI push: none

There is **no** `Microsoft.Maui.*` push notification API. Remote push on MAUI means binding the platform SDKs yourself or using a community plugin.

### Azure Notification Hubs

- **There is no Azure Notification Hubs client SDK for .NET MAUI.** Microsoft's own MAUI migration doc and community Q&A are consistent on this: *"Specific Azure Notification Hub SDKs aren't provided for .NET for Android, .NET for iOS, and .NET MAUI"*, and *"Currently Azure Notification Hubs does not support MAUI applications."*
- The Azure SDK for .NET's `Microsoft.Azure.NotificationHubs` package is a **server-side** management/send SDK. It is not a device SDK.
- Practical pattern: register the device with FCM/APNs natively, then POST the token to ANH's REST installation API (or to your own relay), and let ANH fan out. Microsoft's *"Migrate Azure Notification Hub code from Xamarin.Forms to .NET MAUI"* doc walks this path. Community sample: `Xcelerator-Group/dotnet-maui-notifications`.
- **ANH on MAUI Windows (WinUI/Windows App SDK) is explicitly not supported** — irrelevant for you, but worth knowing.
- No credible evidence of an ANH retirement announcement was found. The FCM *legacy* HTTP API deprecation (Google, mid-2024) forced everyone onto **FCM v1**; that migration is done.

### The practical MAUI push stack

| Library | Version | Notes |
|---|---|---|
| **`Plugin.FirebasePushNotifications`** (thomasgalliker) | **3.2.11** | The de-facto choice. Handles Android + APNs, token lifecycle, permissions, background notifications, topics. Actively maintained. |
| `Plugin.Firebase.CloudMessaging` | 4.0.1 | Part of the broader `Plugin.Firebase` family. Requires uploading an APNs auth key to the Firebase console. |
| `Shaunebu.MAUI.FirebasePushNotifications` | — | Newer, lighter alternative. |
| Direct bindings | — | `Xamarin.Firebase.Messaging` / `Xamarin.Firebase.iOS.CloudMessaging` bindings, wired by hand. Most control, most work. |

### Assessment

**3/5, and a modest loss vs Expo.** Expo's `expo-notifications` + EAS push credentials management is materially smoother than MAUI's — MAUI requires you to hand-manage `google-services.json`, `GoogleService-Info.plist`, APNs auth keys, entitlements, and background modes yourself, and the plugin is community-maintained rather than first-party. Everything is achievable; nothing is delightful.

**One MAUI-specific advantage worth noting:** if you already run an Azure-hosted relay for Azure DevOps service hooks (per research doc `06-notification-relay-and-extension.md`), the server side is C# either way — but that's true regardless of client framework.

---

## 6. Developer experience and delivery

### Versions and dates (current as of 2026-09-10)

| Release | GA | End of support | Notes |
|---|---|---|---|
| **.NET MAUI 10** | **2025-11-11** | **2027-05-11** | Current shipping. Latest patch **10.0.101** (2026-09-07). |
| .NET MAUI 9 | 2024-11-12 | **2026-05-12** (passed) | Do not start here. |
| .NET MAUI 8 | 2023-11-14 | 2025-05-14 (passed) | — |
| **.NET MAUI 11** | **2026-11-10** (scheduled) | ~2028-05 | Currently **RC 1**. STS (2-year) release. |

**Important support-policy gotcha:** .NET 10 is an LTS release supported to **November 2028**, but **.NET MAUI 10 is only supported to 2027-05-11**. MAUI follows the *Modern Lifecycle* with a minimum 6-month overlap after a successor ships — it does **not** inherit .NET's 3-year LTS window. You must also be on the **latest servicing patch** to get Microsoft support. **Practically: plan to upgrade the MAUI workload annually, forever.** This is a hidden recurring cost RN/Expo also has (Expo SDK yearly), so call it a wash — but do not budget as if "LTS" means three quiet years.

### Hot reload quality in 2026

Historically MAUI's weakest point (2022–2023: *"memory leaks, rendering inconsistencies, slow hot reload"*). **Materially improved, and .NET 11 is the inflection point:**

- **XAML Incremental Hot Reload** (.NET 11 Preview 7): a source generator plus `MetadataUpdateHandler` produces *patches* for edits to `x:Class`-backed XAML and applies them **to every live instance of the affected type** — so already-instantiated pages update without being recreated or re-navigated. Supported edits: properties, bindings, page/control-scoped resources, and adding/removing/reordering child elements. Enabled by default in Debug; opt out with `EnableMauiIncrementalHotReload=false`.
- **`dotnet watch` for Android** (.NET 11 Preview 4): deploys to device/emulator and applies Hot Reload on edit.
- **`dotnet watch` for iOS** (.NET 11 Preview 4): now usable end-to-end on the Simulator (a `UIKitSynchronizationContext` deadlock was fixed in `dotnet/sdk#54023`). **Caveat, still open:** *"`dotnet watch` does not work for iOS projects unless `<MtouchLink>None</MtouchLink>` is set in the `.csproj`"* (`dotnet/macios#25295`).
- Third-party measurements (Syncfusion) claim ~40% dev-speed improvement from Hot Reload 2.0. **Treat vendor numbers as marketing.**

**Honest comparison:** this is now *good* — but Metro + Fast Refresh in RN is still faster, more reliable, and does not require a device deploy. And C# code changes beyond Hot Reload's scope still need a redeploy. **Call it RN by a clear but no longer embarrassing margin.**

### Build times

Real numbers from the .NET 11 RC 1 release notes (Release CoreCLR MAUI sample-content app, Android):
- Managed source change: **68.32s → 52.31s**
- Manifest change: **39.74s → 10.97s**
- Type map generation, clean build: **3,204ms → 792ms**
- VS design-time builds no longer invoke `aapt2` — some unit-test design-time builds went from **>2s to <600ms**.
- Command-line `dotnet build` now uses `System.IO.Compression.ZipArchive` for `.apk`/`.aab` creation (faster than the previous libzipsharp path); VS builds still use libzipsharp.

**Assessment:** iterating on a MAUI app is measured in **tens of seconds**; a Metro reload is measured in **hundreds of milliseconds**. Over a multi-month project this is a real productivity delta, partially but not fully offset by Hot Reload.

### CI

- **iOS builds require macOS runners.** Same constraint as RN — but RN teams routinely offload this to **EAS Build**, which has no MAUI equivalent.
- **GitHub Actions macOS pricing (2026): ~$0.062/minute**, and macOS minutes drain the included allowance at a **10x multiplier**. Standard advice is to run Android on Windows/Linux runners and reserve macOS strictly for the iOS job, with hard `timeout-minutes` to avoid runaway cost.
- Tooling exists and is well-trodden (`.NET MAUI - Apple Provisioning` marketplace action; multiple community pipeline write-ups; Microsoft's own DevOps-for-MAUI content).
- **Assessment: 3/5, roughly parity with bare RN, a loss vs Expo/EAS.**

### OTA updates — confirmed: none

**Confirmed. There is no .NET MAUI equivalent to EAS Update.**

- Microsoft announced App Center's retirement in **April 2024**; the service shut down **2025-03-31**. **CodePush was bundled into App Center and died with it. There was no successor.**
- Every viable OTA option in 2026 (EAS Update, Capgo, `hot-updater`, Pushy, Appflow, Bitrise CodePush, self-hosted code-push servers) targets **React Native, Capacitor, Ionic, or Cordova** — i.e. JavaScript-bundle-based runtimes. None supports MAUI, and none *can*, because MAUI ships compiled managed assemblies that both Apple and Google forbid you from replacing at runtime.
- **Partial workaround, with caveats:** in a **Blazor Hybrid** or `HybridWebView` app, the *web assets* (Razor-rendered HTML/CSS/JS, or your Monaco/diff bundle) could in principle be fetched and cached from a server, giving you a limited OTA channel for the web-rendered portions. **Apple App Store Review Guideline 3.3.2 permits this** for interpreted code that does not change the app's primary purpose — it is the same legal basis EAS Update relies on. But: you would be building this yourself from scratch, with your own versioning, rollback, staged-rollout, and integrity story. **Mark as: technically feasible, non-trivial, unverified in practice for MAUI. Budget 2–4 weeks if you need it, and get legal/review sign-off.**

**Cost of the gap for this app, concretely:** Azure DevOps ships REST API changes and new work-item field behaviours continuously. Without OTA, every "the board broke for org X" fix is a 1–3 day App Store review cycle (Apple currently median ~24h, but tail risk is days) plus a user-update-adoption curve measured in weeks. This is a **material operational disadvantage** for a third-party client of a service you do not control.

### App size, startup, NativeAOT

| | Status |
|---|---|
| **NativeAOT on iOS / Mac Catalyst** | **Supported.** Microsoft's measured claims: *"up to 2x faster startup on iOS devices"*, *"1.2x faster on Mac Catalyst"*, and *"more than 2x smaller apps for both iOS and Mac Catalyst"* vs the default Mono deployment. |
| **NativeAOT on Android** | **Not supported** as of .NET 10. Significant work landed in the .NET 10 cycle (`dotnet/runtime#106748`); described as "almost ready" but not shipped. |
| **NativeAOT on Windows** | Planned shortly after .NET 10, possibly via servicing. |
| **CoreCLR** | **.NET 11 Preview 4: CoreCLR is the default runtime on all .NET MAUI platforms** for projects targeting .NET 11 (announcement: `aka.ms/maui-coreclr`). This unifies runtime behaviour and improves debugging, profiling, Hot Reload, size, and performance — but the Android release notes warn *"a reasonable increase to application size"* vs Mono. **Android API 21/22/23 remain Mono-only.** |
| **ReadyToRun** | .NET 11 Release CoreCLR Android builds include most app-assembly methods in partial R2R: **+2.4% startup for the basic template, +4.5% for sample-content**, at **+64KB / +260KB** package size respectively. |

**Hard constraint you must resolve early:** NativeAOT on iOS is **incompatible with the Azure DevOps client libraries** (Newtonsoft reflection — §3). You can have NativeAOT's 2x startup and 2x size reduction, *or* the free typed models, **not both**. This reinforces the §3 recommendation to hand-write REST with `System.Text.Json` source generation.

**No credible current MB-for-MB "hello world" size comparison against RN was found.** Historically MAUI iOS binaries have been larger than RN's; with NativeAOT + trimming they become competitive. **Mark as unverified — measure it in a spike if size is a decision input.**

### Blazor Hybrid as an alternative UI layer

**This deserves serious consideration and is probably the strongest MAUI *shape* for this specific app.**

**What it gets you:**
- The **entire UI is HTML/CSS/JS-adjacent**, so the diff viewer (Monaco/Shiki), the rich-text editor (Quill/TipTap), and Markdown rendering are all *just web components* — the exact places where native MAUI is weakest (§4b, §4c).
- You keep **100% of the MSAL/broker and Intune wins** — those live in the .NET host, untouched.
- Microsoft's own MAUI auth doc ships a **Blazor Hybrid `AuthenticationStateProvider` implementation** and `<AuthorizeView>` usage, so the auth integration is documented, not improvised.
- Native shell where it matters: navigation, tablet split view, push registration, secure storage, SQLite.
- **.NET 10/11 `HybridWebView`/`BlazorWebView` improvements apply**: `WebResourceRequested` interception, initialization events, JS exceptions surfaced as .NET exceptions, and source-generated JSON for JS↔.NET interop.

**What it costs you:**
- **Render performance.** `dotnet/maui#28667` documents that *"MAUI Blazor Hybrid has worse render performance than Blazor Server and WebAssembly"*, attributed to marshalling between the .NET runtime and the WebView. Community consensus: fine for business apps, not for heavy animation. A Kanban board with drag-and-drop is borderline — **spike the Kanban drag interaction in Blazor Hybrid before committing.**
- **WebView memory bloat** requires discipline (lightweight styling, minimal animation, few synchronous JS-bridge calls).
- **It is Razor and C#, not TypeScript.** This is the point most often glossed over. Your team's HTML/CSS knowledge transfers; their **TypeScript, React, and npm ecosystem knowledge does not**. You would be writing `.razor` files with C# expressions. **Do not sell this internally as "we get to keep our web skills" — it is roughly half true.**
- Native feel is a notch below native MAUI controls, which is itself a notch below RN's platform components.

---

## 7. Ecosystem health

### The 2025 layoffs — what actually happened

- **2025-05-14:** Miguel de Icaza posted publicly: *"Microsoft laid off the senior engineers of .NET on Android and key figures of Maui. This might just be the US wave, so perhaps the whole thing is doomed."* Widely amplified; `dotnet/maui` discussion **#29483** ran 2025-05-14 to 2025-05-25 with substantial community alarm, including teams with multi-year MAUI investments.
- **2025-05-25:** Microsoft's David Ortinau responded on that discussion: *"Our commitment to the longevity of .NET MAUI continues unchanged."* He cited increased MAUI content at Build 2025, more contributors than ever, an updated product roadmap, a strengthened Syncfusion partnership, and VS productivity improvements. Per the thread, this resolved most concerns among engaged participants.

### Evidence of continued investment (2025–2026)

This is where the "is MAUI dying" question is actually settled — by shipping, not statements:

- **.NET MAUI 10 GA on 2025-11-11**, with the stated focus *"to improve product quality"* — the right theme, and the release backs it: default CV2 handlers on iOS, XAML source generator (`MauiXamlInflator=SourceGen`), global/implicit XML namespaces, SafeArea overhaul, `HybridWebView` request interception, deprecation of `ListView`/`TableView`/`Compatibility.Layout`/`MessagingCenter`, layout diagnostics via `ActivitySource`/Meters, and a .NET Aspire service-defaults template.
- **.NET 11 previews shipped continuously through 2026** (Previews 1–7, RC 1 by September), each with real MAUI content: CoreCLR everywhere, `dotnet watch` on Android and iOS, XAML Incremental Hot Reload, Map control improvements (pin clustering, custom icons, JSON styling), Apple Intelligence / Foundation Models bindings, trim-safe `RelativeSource` compiled bindings, Android build-time reductions.
- **Public roadmap** (`dotnet/maui` wiki): investment areas are performance (CoreCLR, NativeAOT, diagnostics), **GitHub Copilot / Copilot Agent integration**, and CLI/SDK instrumentation, on a monthly servicing cadence prioritised by usage, bug severity, and strategic opportunity. Notably it is a **near-term roadmap, not a multi-year commitment** — read that as you like.
- **Vendor investment continues:** Syncfusion shipped a MAUI Kanban to production-ready (2025 Vol 1), a MAUI Rich Text Editor (2025 Vol 3, enhanced 2026 Vol 1), and a MAUI Markdown Viewer; Syncfusion sponsored **.NET MAUI Day London 2026**. Telerik publishes ongoing MAUI content. DevExpress keeps its MAUI suite free. Vendors do not fund dying platforms.
- **Xamarin end of support: 2024-05-01** — the migration forcing function is complete, which means MAUI's user base is now the floor, not a transient.

### Adoption

- **Stack Overflow-derived figures (secondary source — see caveat):** React Native ~**9%** of respondents vs .NET MAUI ~**3.4%**; a summary states React Native and Flutter are *"on average three times more popular than .NET MAUI."* **⚠️ Unverified:** these numbers come from a third-party comparison blog (Scalo, 2026) citing the Stack Overflow survey, not from the survey directly. Treat the ~3:1 ratio as directionally right and the exact figures as soft.
- **Corroborating signal from NuGet:** `Microsoft.Intune.Maui.Essentials.iOS` has ~**38.7K lifetime downloads** (~63/day) and the Android package ~**29.1K**. For comparison, `Microsoft.TeamFoundationServer.Client` has **42.3M**. The MAUI+Intune intersection is a **very small population**. That cuts both ways: it is a thin-ice path with few people ahead of you — **but it is also exactly the moat that would differentiate your product.**
- **Hiring (2026):** ZipRecruiter US averages ~**$53.73/hr** for ".NET MAUI developer" (May 2026) vs ~**$55.01/hr** for "React Native" (Aug 2026) — comparable rates. **Volume is the difference:** React Native job postings vastly outnumber MAUI's. For a small team hiring one or two people, C#-with-mobile-willingness is a larger pool than "MAUI expert"; you will be training, not hiring, MAUI skills.

### Credible 2026 assessments

- **Pro:** Telerik's *"Is .NET MAUI Production-Ready?"* (vendor, biased) points to Microsoft 365 Admin and NBC Sports Next's SportsEngine as shipping MAUI apps. Syncfusion (Feb 2026) claims *"significant maturity in real production environments."* Multiple consultancies converge on: right choice **when the team is already .NET, needs deep Azure integration, is migrating from Xamarin, or wants C# across the stack** — a fair and appropriately conditional framing.
- **Con:** `isthistechdead.com/maui` publishes a "Deaditude Score" of **37.3%** — snark, not analysis, but a decent proxy for sentiment. Michael Stonis' *"XAML in 2026: Time to Move On"* argues XAML is the wrong markup for new MAUI projects (advocating C# Markup) — an insider critique of the *authoring model*, not of the platform's viability.
- **Balanced read:** MAUI in 2026 is **stable, supported, improving, and small**. It is not dying. It is also not growing fast enough to close the ecosystem gap with React Native, and Microsoft's own roadmap language is deliberately near-term. **Risk of abandonment within your app's 3–5 year horizon: low but non-zero.** The mitigating factor is that MAUI is now load-bearing for Microsoft's own first-party mobile apps and for the entire ex-Xamarin enterprise base.

---

## 8. Verdict for this specific app

### Where MAUI clearly beats React Native/Expo

| Area | Margin | Why |
|---|---|---|
| **Intune App Protection Policy / APP-based Conditional Access** | **Decisive** | First-party GA NuGets, Microsoft samples, documented integration path. RN has no supported route — only a community npm wrapper or hand-written native modules around a security SDK that ships breaking changes before every major OS release. **This is the whole argument.** |
| **Brokered Entra auth (Authenticator / Company Portal)** | **Large** | MSAL.NET `WithBroker()` is first-party with a current, MAUI-specific Learn article. RN has no first-party MSAL binding. Device-compliance CA grants, SSO across Microsoft apps, and MAM enrolment all flow from this. |
| **CAE claims-challenge handling** | Moderate | `WithClaims()` + `cp1` is one builder call; RN is a hand-rolled header parse. Now mandatory since ADO CAE reached all customers ~May 2026. |
| **Enterprise credibility / procurement** | Moderate, non-technical | "Built on Microsoft's stack, Intune-managed, brokered auth" is an easier security-review conversation than "React Native with a community MSAL wrapper." For a paid third-party ADO client sold to enterprises, **this is a sales asset, not just an engineering one.** |
| **Same-language backend** | Small | If your notification relay is ASP.NET, shared DTOs and validation are a modest win. |

### Where MAUI loses

| Area | Margin | Why |
|---|---|---|
| **Team skill fit** | **Decisive (given the assumption)** | Full C# + XAML/Razor + MSBuild + iOS/Android bindings ramp. Expect **2–3 months** before the team is productive and **6+ months** before they're good. Blazor Hybrid recovers HTML/CSS but not TypeScript/React. |
| **OTA updates** | **Large** | None, at all, with no path. For a third-party client of an API you don't control, every hotfix is an App Store review cycle. |
| **Diff rendering** | Large | No native control; you write a WebView + Monaco/Shiki solution — the same code you'd write in RN, minus the React ecosystem around it, plus a C#↔JS interop layer. |
| **Rich text** | Moderate | Paid controls (Syncfusion/Telerik) with **unverified fidelity against ADO's HTML dialect**, or a WebView. RN's Quill/TipTap/`react-native-pell-rich-editor` options are free and battle-tested by more teams. |
| **Ecosystem velocity** | Moderate | ~3:1 adoption gap; thinner packages; fewer Stack Overflow answers; longer time-to-unblock on obscure problems. |
| **Inner loop** | Moderate | Tens of seconds vs sub-second. Compounds over a multi-month build. |
| **Recurring licence cost** | Small–Moderate | ~$2–5K/year for Syncfusion/Telerik unless you qualify for Syncfusion Community (strict thresholds, incl. a lifetime $3M outside-capital cap). RN equivalents are free. |
| **"Free Microsoft client libraries"** | **Reverses** | On mobile the ADO .NET client libraries are a **liability** (Newtonsoft + WebApi.Client vs iOS trimming/AOT), not an asset. Do not count this as a MAUI advantage. |

### Estimated relative effort

Baseline = React Native/Expo implementation by this TS/web team = **1.0x**. All figures ±30%; they assume the Syncfusion licence is bought (or Community-eligible).

| Workstream | RN/Expo | MAUI (XAML) | MAUI (Blazor Hybrid) | Notes |
|---|---|---|---|---|
| Team ramp-up | 1.0x (0) | **+2–3 months** | **+1.5–2.5 months** | Pure additive cost. The largest single line item. |
| Auth (interactive Entra, no broker) | 1.0x | 0.8x | 0.8x | MSAL.NET is cleaner than RN's options even without broker. |
| **Auth (brokered + CAE)** | **3.0x** | **1.0x** | **1.0x** | RN must hand-roll or go native. |
| **Intune APP integration** | **6.0x+ / infeasible** | **1.0x** | **1.0x** | RN: unsupported native modules around a mandatory-update security SDK. **The decisive line.** |
| ADO REST client + models | 1.0x | 1.3x | 1.3x | Hand-written STJ either way; C# is more verbose, but source-gen + typed records are pleasant. |
| Kanban + drag-and-drop | 1.0x | 0.8x | 1.4x | Syncfusion `SfKanban` with workflow rules is a genuine shortcut vs building DnD from RN primitives. Blazor Hybrid DnD is the risky one. |
| Work item forms + rich text | 1.0x | 1.5x | 1.0x | ADO HTML fidelity risk on all three; Blazor Hybrid lets you use a proven web editor. |
| **PR diff viewer + line comments** | 1.0x | **2.0x** | **1.2x** | XAML: WebView + interop + a native comment gutter overlay. Blazor Hybrid: mostly web. |
| Markdown rendering | 1.0x | 1.0x | 0.9x | Comparable. |
| Pipelines / builds screens | 1.0x | 1.1x | 1.1x | Standard lists and detail views. |
| Tablet adaptive layouts | 1.0x | 1.3x | 1.1x | `TwoPaneView` + window-size-driven layout vs CSS/flex. |
| Push notifications | 1.0x | 1.6x | 1.6x | Loss of Expo's credential management. |
| Offline / SQLite / secure storage | 1.0x | 0.9x | 0.9x | Slight MAUI edge (EF Core, SQLCipher). |
| CI/CD setup | 1.0x | 1.2x | 1.2x | No EAS Build equivalent. |
| **Ongoing maintenance / hotfixes** | 1.0x | **1.5x** | **1.5x** | No OTA; every fix is a store cycle. Plus mandatory Intune SDK updates and annual MAUI workload upgrades. |

**Aggregate for the app as scoped:**
- **Without an Intune requirement:** MAUI (XAML) ≈ **1.5–1.8x** RN/Expo, plus 2–3 months ramp. MAUI (Blazor Hybrid) ≈ **1.2–1.4x**, plus 1.5–2.5 months ramp. **RN wins clearly.**
- **With a hard Intune APP requirement:** RN's Intune workstream alone plausibly costs **2–4 months of unsupported native work with real risk of never fully working** (and no vendor to escalate to when it breaks after an iOS major release). **MAUI wins, decisively**, despite being more expensive everywhere else.

### Recommendation

1. **Determine, first and before anything else, whether "Require app protection policy" Conditional Access is a hard requirement from named prospects.** Not "would be nice." Not "enterprises like Intune." **Named customers who will not buy without it.** This single question dominates the decision and everything else is secondary.
2. **If no:** stay on React Native/Expo. Nothing else in this evaluation justifies the switch for a TypeScript team, and several factors (OTA, inner loop, ecosystem, skill fit) argue strongly against it.
3. **If yes:** choose **MAUI Blazor Hybrid**, not MAUI XAML. It preserves the entire auth/Intune advantage — which lives in the .NET host and is untouched by the UI choice — while putting your hardest UI surfaces (diff viewer, rich text, Markdown) back into web technology where your team can actually be productive. Then:
   - **Spike Kanban drag-and-drop in Blazor Hybrid first.** It is the one place Blazor Hybrid's WebView render performance could genuinely fail (`dotnet/maui#28667`). If it does, fall back to a **hybrid-of-the-hybrid**: native XAML `SfKanban` for the board, Blazor/`HybridWebView` for diffs and rich text. MAUI supports mixing these in one app.
   - **Spike ADO work-item HTML round-tripping** through your chosen editor. Top-3 risk on any framework.
   - **Skip the ADO .NET client libraries.** Hand-write REST with `System.Text.Json` source generation. This keeps NativeAOT-on-iOS viable and avoids the Newtonsoft/trimming minefield entirely.
   - **Start the Intune App Partner registration immediately** — questionnaire at `aka.ms/IntuneAppPartner`, then a signed partner agreement, then a monthly service-update cycle to publish your deep link. **1–3 months lead time, and it needs legal.** Meanwhile, tell pilot customers to target you via **Custom Apps** by bundle ID / package name, which works from day one.
   - **Budget the standing tax:** mandatory Intune SDK updates before every major iOS/Android release, and an annual MAUI workload upgrade (MAUI 10 support ends **2027-05-11**, regardless of .NET 10 being LTS to 2028).
4. **A fourth option worth costing, if the Intune answer is "yes" but the team is adamant about TypeScript:** ship the RN/Expo app as the primary product, and build a **separate, small MAUI (or fully native) "managed" build** for Intune-gated enterprise customers, sharing only the backend. Doubles the client surface but keeps the mainline product velocity. Only sensible if the enterprise segment is a small, high-value minority — evaluate against the segment's revenue.

---

## Explicitly unverified claims

Marked here so they are not mistaken for established fact:

1. **Azure DevOps .NET client libraries running successfully on MAUI iOS/Android.** No Microsoft statement, sample, or support commitment exists. `netstandard2.0` guarantees only that they *reference*. **Requires a Release-configuration spike on a physical iPhone with trimming enabled.** (§3)
2. **Syncfusion/Telerik RichTextEditor fidelity with Azure DevOps HTML fields.** No vendor documents ADO compatibility. **Requires a round-trip spike with real work-item HTML — including pasted Word content, nested lists, inline images, and tables.** (§4b)
3. **MAUI `SecureStorage` size limits.** No documented per-value limit was found in Microsoft's docs. The 2KB figure in the brief is Expo `SecureStore`'s documented limit, not MAUI's. **Treat MAUI's limit as unknown; do not design around it — use MSAL's own token cache for tokens.** (§4g)
4. **Stack Overflow 2026 adoption figures (RN ~9%, MAUI ~3.4%).** Sourced from a third-party comparison blog citing the survey, not the survey itself. Directionally reliable (~3:1); exact figures soft. (§7)
5. **MAUI vs RN app size in MB.** No credible current head-to-head found. Microsoft's NativeAOT claims (>2x smaller than Mono, ~2x faster startup on iOS) are relative to MAUI's own baseline, not to React Native. **Measure if size is a decision input.** (§6)
6. **Blazor Hybrid Kanban drag-and-drop performance.** Extrapolated from the documented general Blazor Hybrid render-performance issue (`dotnet/maui#28667`); no specific Kanban benchmark exists. **This is the single highest-risk unverified item in the recommended path — spike it first.** (§6, §8)
7. **Web-asset OTA via Blazor Hybrid / `HybridWebView`.** Technically plausible and consistent with App Store Review Guideline 3.3.2, but no MAUI-specific precedent, tooling, or Microsoft guidance was found. Entirely self-built. (§6)
8. **Azure Notification Hubs long-term viability.** No retirement announcement found, but also no MAUI client SDK and no sign of MAUI investment. Low confidence in future first-party support. (§5)
9. **Effort multipliers in §8.** Engineering judgement calibrated against the researched maturity findings, not measured data. ±30% at best, and highly sensitive to the TypeScript-team assumption stated at the top of this document.

---

## Citations

**MSAL.NET / authentication**
- Authenticate users with MSAL.NET — .NET MAUI (updated 2026-03-20): https://learn.microsoft.com/en-us/dotnet/maui/data-cloud/authentication?view=net-maui-10.0
- Microsoft Authentication Library for .NET: https://learn.microsoft.com/en-us/entra/msal/dotnet/
- `Microsoft.Identity.Client.Broker` namespace: https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.broker?view=msal-dotnet-latest
- Leveraging the broker on iOS and Android (MSAL.NET wiki): https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/wiki/Leveraging-the-broker-on-iOS-and-Android
- Authentication for .NET MAUI Apps with MSAL.NET (.NET Blog): https://devblogs.microsoft.com/dotnet/authentication-in-dotnet-maui-apps-msal/
- MAUI MSAL sample: https://github.com/Azure-Samples/ms-identity-dotnetcore-maui
- MSAL.NET MAUI compatibility issue #3127: https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/3127
- MAUI auth docs request #3228: https://github.com/dotnet/docs-maui/issues/3228
- `Microsoft.Identity.Client` on NuGet (4.88.0): https://www.nuget.org/packages/microsoft.identity.client
- Android advisory GHSA-x674-v45j-fwxw (MSAL.NET 4.48.0–4.60.3): https://github.com/advisories/GHSA-x674-v45j-fwxw
- Error handling in MSAL.NET: https://learn.microsoft.com/en-us/entra/msal/dotnet/advanced/exceptions/msal-error-handling
- Claims challenges, claims requests, client capabilities: https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge
- CAE-enabled APIs in your applications: https://learn.microsoft.com/en-us/entra/identity-platform/app-resilience-continuous-access-evaluation
- Continuous access evaluation in Microsoft Entra: https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation
- MSAL + Azure DevOps token issue #1671: https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/1671

**Azure DevOps**
- Real-Time Security with CAE comes to Azure DevOps (2025-08-12; updated 2026-04-17): https://devblogs.microsoft.com/devops/real-time-security-with-continuous-access-evaluation-cae-comes-to-azure-devops/
- Conditional Access policies on Azure DevOps: https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops
- .NET client libraries — Azure DevOps (updated 2026-07-23): https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/dotnet-client-libraries?view=azure-devops
- `Microsoft.TeamFoundationServer.Client` on NuGet (20.256.2, 2026-03-11): https://www.nuget.org/packages/microsoft.teamfoundationserver.client/
- `Microsoft.VisualStudio.Services.Client` on NuGet: https://www.nuget.org/packages/Microsoft.VisualStudio.Services.Client/
- .NET/C# samples for Azure DevOps: https://github.com/Microsoft/azure-devops-dotnet-samples

**Intune**
- Get Started With the Microsoft Intune App SDK (updated 2026-07-01): https://learn.microsoft.com/en-us/intune/developer/app-sdk/quickstart-integration
- `Microsoft.Intune.Maui.Essentials.iOS` (21.8.0, 2026-08-25): https://www.nuget.org/packages/Microsoft.Intune.Maui.Essentials.iOS
- `Microsoft.Intune.Maui.Essentials.android` (12.4.0, 2026-06-22): https://www.nuget.org/packages/Microsoft.Intune.Maui.Essentials.android
- MAUI iOS Intune sample: https://github.com/microsoftconnect/sample-intune-maui-ios
- Intune SDK / .NET 9 blocker `dotnet/maui#31860` (closed): https://github.com/dotnet/maui/issues/31860
- App-based Conditional Access policies with Intune: https://learn.microsoft.com/en-us/intune/device-security/conditional-access-integration/app-based-policies
- CA — Require approved app or app protection policy: https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-approved-app-or-app-protection
- Conditional Access: Grant controls: https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-grant
- App Protection Policies overview: https://learn.microsoft.com/en-us/intune/app-management/protection/overview
- Intune App SDK for iOS — React Native support requests: https://github.com/msintuneappsdk/ms-intune-app-sdk-ios/issues/218 and https://github.com/msintuneappsdk/ms-intune-app-sdk-ios/issues/21
- `react-native-ms-intune-mam` (community): https://www.npmjs.com/package/react-native-ms-intune-mam

**.NET MAUI platform**
- What's new in .NET MAUI for .NET 10: https://learn.microsoft.com/en-us/dotnet/maui/whats-new/dotnet-10?view=net-maui-10.0
- What's new in .NET MAUI for .NET 11 (updated 2026-09-09): https://learn.microsoft.com/en-us/dotnet/maui/whats-new/dotnet-11?view=net-maui-10.0
- .NET MAUI support policy (GA/EOS dates): https://dotnet.microsoft.com/en-us/platform/support/policy/maui
- .NET MAUI roadmap wiki: https://github.com/dotnet/maui/wiki/roadmap
- Native AOT deployment on iOS and Mac Catalyst: https://learn.microsoft.com/en-us/dotnet/maui/deployment/nativeaot?view=net-maui-10.0
- Runtimes and compilation in .NET MAUI: https://learn.microsoft.com/en-us/dotnet/maui/deployment/runtimes-compilation?view=net-maui-10.0
- NativeAOT status for Android `dotnet/runtime#106748`: https://github.com/dotnet/runtime/issues/106748
- .NET MAUI Performance Features in .NET 9: https://devblogs.microsoft.com/dotnet/dotnet-9-performance-improvements-in-dotnet-maui/
- XAML Hot Reload for .NET MAUI: https://learn.microsoft.com/en-us/dotnet/maui/xaml/hot-reload?view=net-maui-10.0
- CollectionView docs: https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/collectionview/?view=net-maui-10.0
- Broken virtualization regression `dotnet/maui#18639`: https://github.com/dotnet/maui/issues/18639
- Android CollectionView scrolling discussion `dotnet/maui#18027`: https://github.com/dotnet/maui/discussions/18027
- TwoPaneView layout: https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/twopaneview?view=net-maui-8.0
- .NET MAUI for Android and cross-platform apps (Surface Duo blog): https://devblogs.microsoft.com/surface-duo/net-maui-android-foldable/
- Secure storage migration doc: https://learn.microsoft.com/dotnet/maui/migration/secure-storage
- Blazor Hybrid render performance `dotnet/maui#28667`: https://github.com/dotnet/maui/issues/28667
- Newtonsoft Release-build failures `dotnet/maui#13033`: https://github.com/dotnet/maui/issues/13033
- Generics/JIT in aot-only mode `dotnet/maui#8122`: https://github.com/dotnet/maui/issues/8122
- iOS Release-mode JsonSerializationException `dotnet/maui#27374`: https://github.com/dotnet/maui/issues/27374
- .NET 11 Preview 6 roundup (VS Magazine, 2026-07-15): https://visualstudiomagazine.com/articles/2026/07/15/net-11-preview-6-roundup-aspnet-core-maui-c-ef-core-and-sdk-updates.aspx
- .NET 11 Preview 2 MAUI (InfoQ, 2026-03): https://www.infoq.com/news/2026/03/net-11-preview2-maui/
- .NET 10 arrives (VS Magazine, 2025-11-12): https://visualstudiomagazine.com/articles/2025/11/12/net-10-arrives-with-ai-integration-performance-boosts-and-new-tools.aspx

**Push notifications**
- Migrate Azure Notification Hub code from Xamarin.Forms to .NET MAUI: https://learn.microsoft.com/en-us/dotnet/maui/migration/push-notifications?view=net-maui-10.0
- `Plugin.FirebasePushNotifications` (3.2.11): https://www.nuget.org/packages/Plugin.FirebasePushNotifications/
- `thomasgalliker/Plugin.FirebasePushNotifications`: https://github.com/thomasgalliker/Plugin.FirebasePushNotifications
- `Plugin.Firebase.CloudMessaging` (4.0.1): https://www.nuget.org/packages/Plugin.Firebase.CloudMessaging/
- MAUI + Azure Notification Hub sample: https://github.com/Xcelerator-Group/dotnet-maui-notifications
- MAUI FCM v1 discussion `dotnet/maui#26037`: https://github.com/dotnet/maui/discussions/26037

**UI controls and licensing**
- Syncfusion .NET MAUI Kanban Board — getting started: https://help.syncfusion.com/maui/kanban-board/getting-started
- Syncfusion Kanban columns / placeholder: https://help.syncfusion.com/maui/kanban-board/column
- Syncfusion Kanban workflows: https://help.syncfusion.com/maui/kanban-board/workflows
- Syncfusion Kanban events (DragOver): https://help.syncfusion.com/maui/kanban-board/events
- Introducing the New .NET MAUI Kanban Board: https://www.syncfusion.com/blogs/post/new-dotnet-maui-kanban-board-control
- Syncfusion Essential Studio 2025 Volume 1 (Kanban production-ready): https://www.syncfusion.com/blogs/post/essential-studio-2025-volume-1
- .NET MAUI Rich Text Editor Released (2025 Vol 3): https://www.syncfusion.com/blogs/post/rich-text-editor-dotnet-maui
- Syncfusion Essential Studio 2026 Volume 1: https://www.syncfusion.com/blogs/post/essential-studio-2026-volume-1
- Syncfusion .NET MAUI Markdown Viewer: https://www.syncfusion.com/maui-controls/maui-markdown-viewer
- Syncfusion Community License: https://www.syncfusion.com/products/communitylicense
- Syncfusion Essential Studio pricing: https://www.syncfusion.com/sales/pricing
- Syncfusion .NET MAUI licensing (ComponentSource): https://www.componentsource.com/product/syncfusion-essential-studio-for-net-maui/licensing
- Telerik UI for .NET MAUI: https://www.telerik.com/maui-ui
- Telerik .NET MAUI RichTextEditor: https://www.telerik.com/maui-ui/documentation/controls/richtexteditor/overview
- Telerik .NET MAUI purchase: https://www.telerik.com/purchase/maui-ui
- Telerik — improve CollectionView performance: https://www.telerik.com/maui-ui/documentation/knowledge-base/improve-collectionview-performance
- DevExpress .NET MAUI (free): https://www.devexpress.com/maui/
- DevExpress MAUI EULA: https://www.devexpress.com/support/eulas/maui.xml
- `Indiko.Maui.Controls.Markdown`: https://github.com/0xc3u/Indiko.Maui.Controls.Markdown
- Shiny.NET Markdown (viewer + editor): https://shinylib.net/controls/markdown/
- `Plugin.Maui.MarkdownView`: https://github.com/Toine-db/Plugin.Maui.MarkdownView
- `Microsoft.Maui.Graphics.Text.Markdig`: https://www.nuget.org/packages/Microsoft.Maui.Graphics.Text.Markdig
- `flynk/maui-monaco`: https://github.com/flynk/maui-monaco
- `lk-code/maui.monaco-editor`: https://github.com/lk-code/maui.monaco-editor

**Delivery / CI / OTA**
- Building and Deploying iOS MAUI Apps with GitHub Actions (2025-08-19): https://praeclarum.org/2025/08/19/maui-cicd.html
- From Commit to IPA: Automating .NET MAUI iOS Builds with GitHub Actions: https://medium.com/medialesson/from-commit-to-ipa-automating-net-maui-ios-builds-with-github-actions-fd8d9d47240b
- .NET MAUI — Apple Provisioning action: https://github.com/marketplace/actions/net-maui-apple-provisioning
- GitHub Actions pricing 2026: https://cicdpipelinecost.com/github-actions-pricing
- GitHub Actions runner pricing (docs): https://docs.github.com/en/enterprise-server@3.14/billing/reference/actions-runner-pricing
- App Center retirement: https://blog.sentry.io/visual-studio-app-center-retirement-why-sentry-is-your-next-step/
- CodePush is dead — RN OTA alternatives: https://rnrescue.dev/blog/react-native-codepush-alternatives
- Best React Native OTA Tools in 2026 (Codemagic): https://blog.codemagic.io/react-native-ota-tools-in-2026/

**Ecosystem**
- MS lays off senior .NET/MAUI engineers — `dotnet/maui` discussion #29483 (incl. David Ortinau's 2025-05-25 response): https://github.com/dotnet/maui/discussions/29483
- Miguel de Icaza, 2025-05-14: https://x.com/migueldeicaza/status/1922409129567563855
- Is Maui ready for Production? `dotnet/maui#22844`: https://github.com/dotnet/maui/discussions/22844
- Is .NET MAUI Production-Ready? (Telerik): https://www.telerik.com/faqs/net-maui/is-dot-net-maui-production-ready
- Flutter vs React Native vs .NET MAUI: Which Framework Wins in 2026? (Scalo — source of the 9% / 3.4% figures): https://www.scalosoft.com/blog/flutter-vs-react-native-vs-net-maui-which-framework-wins-in-2026/
- MAUI vs React Native 2026: Enterprise Comparison (Talk Think Do): https://talkthinkdo.com/blog/dotnet-maui-vs-react-native-2026-enterprise/
- .NET MAUI vs React Native (SaM Solutions, 2026-06): https://sam-solutions.com/blog/net-maui-vs-react-native/
- Is .NET MAUI Dead? — Deaditude Score: https://isthistechdead.com/maui/
- XAML in 2026: Time to Move On (Michael Stonis): https://www.ston.is/blog/maui/xaml-in-2026/
- Syncfusion at .NET MAUI Day London 2026: https://www.syncfusion.com/blogs/post/dotnet-maui-day-london-2026-event-recap
- .NET MAUI developer salary data (ZipRecruiter): https://www.ziprecruiter.com/Jobs/Net-Maui-Developer
- React Native salary data (ZipRecruiter): https://www.ziprecruiter.com/Jobs/React-Native
