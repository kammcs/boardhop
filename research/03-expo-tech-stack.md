# Technical Feasibility & Recommended Stack: Azure DevOps Mobile Client (React Native + Expo)

**Prepared:** 2026-09-10
**Scope:** iOS + Android, phone and tablet/iPad, blending Jira Mobile (work items, boards) and GitHub Mobile (PR review with diffs) UX for Azure DevOps.
**Method:** Web research against public docs, changelogs, npm/GitHub metadata, and community sources current as of September 2026. Anything not independently confirmed is flagged **[unverified]**.

---

## Executive Summary

Building this app on Expo in September 2026 is **technically feasible with no hard blockers**, but it requires an **EAS Dev Client** (not Expo Go) from day one because of native auth (Entra ID/MSAL-style OAuth), background/push needs, and possibly native diff/text libraries. The current baseline is **Expo SDK 57** (React Native 0.86, React 19.2), which — like SDK 55/56 before it — runs **only on the New Architecture** (Fabric + TurboModules); the old architecture is no longer selectable. This is a net positive for the app's most demanding surfaces (large PR diffs, Kanban drag-and-drop, Reanimated-based gestures).

The riskiest parts of the product are not Expo itself but three ecosystem gaps:

1. **Tablet/iPad master-detail navigation** is still immature in Expo Router. The official `expo-router/unstable-split-view` API is explicitly **alpha, iOS-only, and not production-ready**. Plan to hand-roll a responsive two-pane layout with standard Expo Router (stacks nested inside a persistent side panel) rather than depend on this API for v1, and treat Android/tablet split-view as a custom `useWindowDimensions`-driven layout.
2. **HTML rendering and rich-text editing** for Azure DevOps work item descriptions is the single biggest maintenance risk. `react-native-render-html` (the long-time default) is **effectively unmaintained**; its authors (Software Mansion) shipped a drop-in fork, **`@native-html/render`**, and recommend migrating. Rich-text *editing* candidates (`react-native-pell-rich-editor`, `react-native-cn-quill`) are stale; **TenTap (`@10play/tentap-editor`)**, a WebView/ProseMirror-based editor, is the most actively maintained option and requires a dev client (Expo Go only supports its basic mode).
3. **Push notifications require a backend**, because Azure DevOps has no built-in mobile push. A small webhook-receiver + device-token-registry service (Service Hooks → your API → Expo Push API) is mandatory scope, not optional polish — budget for it as a first-class backend component, not a stretch goal.

For diffs, no mobile-native diffing widget exists in the RN ecosystem comparable to GitHub's own. The recommended approach is to **compute diffs client-side** with the `diff` npm package (Myers algorithm, the same lineage jsdiff/GitHub-adjacent tools use) against the two full file blobs Azure DevOps' PR Iterations/Changes API returns, then render a virtualized, syntax-highlighted line list with **Shopify's FlashList v2** and a lightweight highlighter (`react-native-code-highlighter`, built on `react-syntax-highlighter`/Prism, or the newer JSI-backed `react-native-shiki-engine` if richer grammar fidelity is needed).

Data layer, state, storage, and auxiliary capabilities (image picking, biometrics, clipboard, haptics, deep links) are all in a mature, low-risk state: TanStack Query + `react-native-mmkv` (now a Nitro/JSI module, ~30x faster than AsyncStorage) + `expo-secure-store` for tokens is the industry-default pattern in 2026. Kanban drag-and-drop across columns has no single dominant library — `react-native-draggable-flatlist` handles in-column reordering well but not cross-list drag, so cross-column Kanban likely needs a Reanimated+Gesture-Handler custom build (using a library like `react-native-dnd`/`react-native-reanimated-dnd` as a foundation) rather than an off-the-shelf Trello clone.

Finally, the app name **cannot start with or be** "Azure DevOps" per Microsoft's trademark guidelines — the convention used by existing third-party clients (e.g., "Mobile Boards for Azure DevOps") is "\<Your Brand\> for Azure DevOps," with a clear "not affiliated with Microsoft" disclosure.

---

## Recommended Stack Table

| Concern | Library / Service | Version (as of 2026-09) | Maturity / Risk |
|---|---|---|---|
| Framework | Expo SDK | 57 | Mature; SDK 57 is a deliberately small, low-risk release |
| Native runtime | React Native | 0.86 | Mature; New Architecture only |
| UI runtime | React | 19.2 | Mature |
| Architecture | New Architecture (Fabric/TurboModules) | mandatory since SDK 55 | Mature; no legacy fallback available |
| Routing | Expo Router | v7 (bundled with SDK 55+) | Mature for stacks/tabs; **alpha/high-risk** for `unstable-split-view` tablet layout |
| Build/Release | EAS Build, EAS Update, EAS Submit | current cloud service | Mature; usage-based pricing, free tier has monthly build caps |
| Dev workflow | expo-dev-client (custom dev build) | bundled | Mature; required — Expo Go cannot host MSAL/native OAuth |
| Diff computation | `diff` (jsdiff) | 5.x | Mature, Myers-algorithm based, widely used |
| Diff/code rendering | `react-native-code-highlighter` + `react-syntax-highlighter`/Prism | current | Moderate maturity; small maintainer base |
| Diff/code rendering (alt.) | `react-native-shiki-engine` | early (JSI/Oniguruma) | New/niche — evaluate as v2 upgrade, not v1 default |
| List virtualization | `@shopify/flash-list` | v2 | Mature; Shopify-maintained, rewritten for New Architecture |
| HTML rendering | `@native-html/render` (fork of react-native-render-html) | current | Actively maintained (2026); prefer over the original package |
| Markdown rendering | `@docren/react-native-markdown` or `@ronradtke/react-native-markdown-display` | current | `react-native-markdown-display` (original) is unmaintained — use a fork |
| Rich text editing | `@10play/tentap-editor` (TenTap, Tiptap/ProseMirror in WebView) | current | Actively maintained; needs dev client for full feature set |
| Images w/ auth headers | `expo-image` | bundled w/ SDK | Mature; supports `source.headers` for Authorization-gated images |
| Data fetching/cache | `@tanstack/react-query` | v5 | Mature, de facto standard |
| Offline persistence | `@tanstack/query-sync-storage-persister` + `persistQueryClient` (or `experimental_createQueryPersister`) | current | Mature pattern |
| Fast local storage | `react-native-mmkv` | v4 (Nitro module) | Mature; requires dev client (not in Expo Go) |
| Secure token storage | `expo-secure-store` | bundled | Mature |
| Drag-and-drop (lists) | `react-native-draggable-flatlist` | current | Mature for single-list reorder; not built for cross-column Kanban |
| Drag-and-drop (custom Kanban) | `react-native-reanimated` + `react-native-gesture-handler` (+ `react-native-dnd`/`react-native-reanimated-dnd` as base) | current | Requires custom engineering; no turnkey cross-column Kanban lib |
| Push notifications | `expo-notifications` + Expo Push API + custom backend | bundled + custom | Mature client SDK; **backend is custom-build, non-optional** |
| Background refresh | `expo-background-task` | bundled (replaces `expo-background-fetch`) | Mature but iOS-throttled by design (no guaranteed interval) |
| Auth (Entra ID/OAuth) | `expo-auth-session` (generic OAuth) or `react-native-msal`/`react-native-app-auth` (native MSAL-class) | current | Native MSAL libs need dev client; evaluate token refresh/conditional-access needs before choosing |
| Deep/universal links | `expo-linking` + Associated Domains / App Links | bundled | Mature |
| Biometrics | `expo-local-authentication` | bundled | Mature |
| Image picking | `expo-image-picker` | bundled | Mature |
| Clipboard | `expo-clipboard` | bundled | Mature |
| Haptics | `expo-haptics` | bundled | Mature |
| @mention autocomplete | `react-native-controlled-mentions` | current | Small library, actively used; low risk for this scope |

---

## 1. Expo Baseline

- **Latest SDK:** Expo SDK 57, released **June 30, 2026**, shipping **React Native 0.86** and **React 19.2**. SDK 57 was intentionally scoped as "a small, focused release" whose main job was the React Native 0.85→0.86 bump with zero intended breaking changes. ([expo.dev/changelog/sdk-57](https://expo.dev/changelog/sdk-57))
- **New Architecture:** Mandatory, not optional. Starting with **SDK 55** (Feb 25, 2026, RN 0.83/React 19.2), the legacy architecture was dropped entirely — "New Architecture is the default" and cannot be disabled. SDK 56 (May 21, 2026, RN 0.85) and SDK 57 both continue on this New-Architecture-only model. Practical effect: every third-party native module you add must be New-Architecture compatible (Fabric + TurboModules); there is no bridge fallback. ([expo.dev/changelog/sdk-55](https://expo.dev/changelog/sdk-55), [x.com/expo](https://x.com/expo/status/2026811977990025364), [docs.expo.dev/guides/new-architecture](https://docs.expo.dev/guides/new-architecture/))
- **Expo Router:** v7 ships with SDK 55+. Typed Routes are a stable, supported feature — Expo Router statically types routes so invalid links fail type-checking. ([docs.expo.dev/router/introduction](https://docs.expo.dev/router/introduction/))
- **EAS Build / Update / Submit:** All three remain the standard cloud pipeline. EAS Build compiles native binaries in the cloud ($1–$4/build style consumption, or bundled credits on paid plans); EAS Update does over-the-air JS/asset updates, now with **Hermes bytecode diffing** in SDK 55+ cutting OTA update payload size to roughly 25% of previous size; EAS Submit uploads the built binary to App Store Connect / Google Play Console. Free tier: 15 iOS + 15 Android builds/month, updates to 1,000 MAUs, 100 GiB edge bandwidth. Paid "Production" plan: $199/mo with $225 build credit, 50,000 MAUs, 1 TiB bandwidth, then usage-based overage ($0.10/GiB bandwidth, $0.05/GiB storage). ([docs.expo.dev/billing/usage-based-pricing](https://docs.expo.dev/billing/usage-based-pricing/), [x.com/expo](https://x.com/expo/status/2026811977990025364))
- **Dev client vs. Expo Go:** Expo Go ships a fixed, non-extensible set of native modules and explicitly **cannot accurately simulate OAuth/native-auth flows**. Because this app needs Entra ID/MSAL-class authentication (custom URL schemes, native token broker behavior), **`expo-dev-client` (a custom EAS development build) is required from the start of the project**, not an optional upgrade later. The same applies to `react-native-mmkv` and any native drag-and-drop/syntax-highlighting module chosen. ([medium.com/@pamudasansika](https://medium.com/@pamudasansika/expo-go-vs-expo-dev-client-which-one-should-you-actually-use-1538f6aae194), [clerk.com](https://clerk.com/articles/expo-go-or-development-build-building-production-ready-authentication-with-clerk))

---

## 2. Tablet / iPad Support

- **`supportsTablet`:** Standard `app.json` config — `expo.ios.supportsTablet: true` opts the app into full iPad support (vs. running letterboxed as an iPhone app). `isTabletOnly` and `requireFullScreen` are related iOS-only flags; `expo.orientation` (root-level: `"default" | "portrait" | "landscape"`) controls allowed orientations, with the caveat that iPad ignores single-orientation locks whenever Split View/Slide Over multitasking is engaged unless you actively manage it via `expo-screen-orientation`. ([medium.com/@ikrammohdabdul](https://medium.com/@ikrammohdabdul/a-complete-go-through-on-app-json-in-react-native-expo-d0123157c8f3), GitHub expo/expo issue threads on orientation)
- **Split view / master-detail in Expo Router:** Expo shipped an **`expo-router/unstable-split-view`** module (SDK 55+) that wraps platform-native split view components (`SplitView.Column`, `SplitView.Inspector`) for master-detail UX. Critically, **it is iOS-only, alpha, "subject to breaking changes," and explicitly not production-ready**; on Android and web it silently falls back to a plain single-pane `Slot` navigator. **Recommendation:** do not build v1's tablet IA around this API. Instead, implement master-detail manually: a persistent layout (`useWindowDimensions`/breakpoint check) that, above a width threshold (e.g., ≥ 768–834dp), renders a list pane and a nested Expo Router `<Stack>`/detail pane side-by-side inside a custom layout route, and collapses to normal push/pop stack navigation below that threshold. Revisit `unstable-split-view` as it stabilizes. ([docs.expo.dev/versions/latest/sdk/router/split-view](https://docs.expo.dev/versions/latest/sdk/router/split-view/), [github.com/expo/router discussion #664](https://github.com/expo/router/discussions/664))
- **Android large-screen / foldables:** Android's large-screen mandate has teeth in this cycle: **Android 17 (API 37) ignores per-app orientation and resizability locks on any device with ≥600dp smallest width**, and by **August 2027** every Play Store app/update must target API 37. Phone-only, portrait-locked layouts are explicitly called out as no longer acceptable on tablets/foldables/desktop windows starting with this generation. This directly validates building the responsive/adaptive layout approach above rather than relying on orientation locks. ([developer.android.com/guide/topics/large-screens](https://developer.android.com/guide/topics/large-screens), [buildmvpfast.com Android 17 mandate](https://www.buildmvpfast.com/blog/android-17-adaptive-resizability-mandate-2026))
- **iPad multitasking:** Split View/Slide Over on iPadOS means the app's window can be as narrow as roughly half an iPad's width at any time; combined with the Android mandate above, the practical engineering requirement is the same on both platforms — **build against window/size-class breakpoints, not device-type checks**.
- **Adaptive layout libraries:** No dominant third-party "adaptive layout" library emerged in research beyond React Native's built-in `useWindowDimensions` + custom breakpoint hooks, and Expo's own (alpha) split-view. Community guides for 2026 converge on hand-rolled hooks keyed to Material "window size classes" / iPad size-class equivalents. **[unverified]** whether any dedicated adaptive-layout npm package has meaningful adoption for this use case as of Sept 2026 — none surfaced as a clear recommendation in research.

---

## 3. Code Diff Rendering on Mobile

**How GitHub Mobile does it:** Research did not surface GitHub's mobile-specific diff rendering internals (native app source is closed); GitHub's engineering blog discusses diff-line performance techniques for the **web** client (isolating diff-line component responsibilities, virtualizing rows, minimizing per-row state) but nothing RN-specific was found. **[unverified]** exact rendering technology in GitHub's iOS/Android apps — treat "no confirmed native diff widget exists to copy" as the working assumption, and design from RN-native primitives instead. ([github.blog engineering diff-lines](https://github.blog/engineering/architecture-optimization/the-uphill-climb-of-making-diff-lines-performant/))

**Computing the diff client-side:** Azure DevOps' PR API does not return a pre-computed diff — the **Pull Request Iteration Changes** endpoint (`GET .../pullRequests/{id}/iterations/{iterationId}/changes`) enumerates changed paths per iteration, and file *content* for each version is fetched separately (Items/blobs API by version). This means the app must diff two full file texts client-side. The standard tool is the **`diff` npm package (jsdiff)**, a Myers-algorithm ("An O(ND) Difference Algorithm and its Variations") text-differencing library with `diffLines`/`createPatch`/`structuredPatch` utilities suited to building a unified diff view; lighter alternatives (`fast-myers-diff`, `myers-diff`) exist if bundle size matters but are lower-level. ([learn.microsoft.com PR Iteration Changes](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get), [npmjs.com/package/diff](https://www.npmjs.com/package/diff))

**Rendering approach (recommended):**
1. Fetch both file blobs (base + target) for a changed path.
2. Run `diff.structuredPatch` (or `diffLines`) to get hunks of added/removed/context lines.
3. Render as a **unified diff by default** (single column, +/− gutter) — cheaper to lay out on narrow phone widths than a split/side-by-side view; offer split view as a tablet/landscape enhancement only, gated behind the same width breakpoint used for master-detail layout.
4. Virtualize the line list with **`@shopify/flash-list` v2** — Shopify's from-scratch rewrite for the New Architecture, JS-only, no item-size estimation required, with reported large gains in scroll smoothness and JS-thread CPU versus `FlatList` on large lists (community reports describe "consistently above 90%" CPU dropping to "consistently below 10%" after migration in one production case study — treat as directional, not benchmarked by this research). This matters directly for large PR diffs (hundreds/thousands of lines). ([shopify.engineering/flashlist-v2](https://shopify.engineering/flashlist-v2), [shopify.github.io/flash-list](https://shopify.github.io/flash-list/))
5. Apply syntax highlighting **per line** (not per file) so highlighting cost is paid only for rendered/visible rows, keeping it compatible with FlashList virtualization.

**Syntax highlighting library choice:**
- `react-native-syntax-highlighter` (conorhastings) — original wrapper around `react-syntax-highlighter`; last clearly-dated activity is old (~2019-era per npm metadata found), best treated as **legacy/at-risk**.
- `react-native-code-highlighter` — newer wrapper with the same `react-syntax-highlighter` (Prism/highlight.js grammars) engine underneath; more actively referenced in current guides. **Recommended default** — good grammar coverage (matches Prism's language set, which covers all languages likely to appear in ADO repos), acceptable performance at line-level granularity.
- **Shiki-in-RN** (`react-native-shiki-engine`) — a newer, JSI-backed approach using a native Oniguruma regex engine binding for "zero bridge overhead," giving VS Code-quality (TextMate grammar) highlighting fidelity. This is more accurate than Prism/highlight.js-based highlighters (same engine VS Code/GitHub.com use) but is a niche/early library — evaluate for a v2 fidelity upgrade rather than v1 dependency, given the added native-module surface and maturity risk. Shiki also has a pure-JS "javascript" engine mode (no WASM) that could theoretically run in RN's JS engine (Hermes) without a native module at all — **[unverified]** whether it performs acceptably per-line at Hermes speeds for large diffs; prototype before committing. ([github.com/skiniks/react-native-shiki-engine](https://github.com/skiniks/react-native-shiki-engine), [npmjs.com/react-shiki](https://www.npmjs.com/react-shiki))

---

## 4. Rich Text / HTML Rendering and Editing

Azure DevOps work item **Description**, **Repro Steps**, and comment fields are stored as HTML by default, with organizations increasingly offered a **Markdown** rendering option for comments/descriptions (per-project process configuration). The app needs both an HTML *renderer* (legacy/HTML-mode items) and a Markdown *renderer*, plus a rich-text (or Markdown-source) *editor* for creating/editing.

**HTML rendering:**
- `react-native-render-html` — the long-standing default — is **no longer maintained**. Its own maintainers (Software Mansion) announced a successor, **`@native-html/render`**, "an official fork... with the exact same API, but it now supports the latest React Native... We will maintain it going forward... the previous package is no longer maintained." **Recommendation: adopt `@native-html/render` directly rather than the legacy package**, since it's a drop-in API replacement. ([x.com/swmansion](https://x.com/swmansion/status/2028867055135432821), [github.com/native-html/render](https://github.com/native-html/render), [npmjs.com/react-native-render-html](https://www.npmjs.com/package/react-native-render-html))
- `@expo/html-elements` remains useful as a set of semantic RN primitives (`<H1>`, `<P>`, `<UL>`, etc.) for hand-rendering simpler HTML fragments or as a target for a custom HTML→RN renderer, but it is not itself a full HTML parser/renderer — it complements rather than replaces `@native-html/render`.

**Markdown rendering:**
- `react-native-markdown-display` — confirmed **unmaintained/"dead"** in multiple 2026 sources. Two live forks/alternatives surfaced: **`@ronradtke/react-native-markdown-display`** (typed, maintained fork) and **`@docren/react-native-markdown`** (rebuilt on `mdast-util-from-markdown`, described as more modern/performant). A third option, **`react-native-enriched-markdown`**, is a from-scratch Fabric/New-Architecture native renderer using `md4c` for CommonMark+GFM parsing with native text selection/accessibility/RTL — attractive for performance but newer/less battle-tested. **Recommendation:** start with `@docren/react-native-markdown` or `@ronradtke/react-native-markdown-display` for lower integration risk; keep `react-native-enriched-markdown` on the radar as a performance upgrade. ([medium.com/@vishamberlal](https://medium.com/@vishamberlal/react-native-markdown-display-is-dead-heres-what-to-use-instead-fb6924f9bb3c))

**Rich text editing:**
- `react-native-pell-rich-editor` — maintenance assessed as **"Inactive"**; latest version ~1 year old at research time, low commit velocity.
- `react-native-cn-quill` — maintainer has stated it's **"no longer actively maintained"** and is soliciting a new maintainer.
- **`@10play/tentap-editor` (TenTap)** — a Tiptap/ProseMirror-based editor rendered in a WebView, explicitly designed for "getting the best experience of editing rich-text on mobile," with New Architecture support (RN ≥0.73.5), custom keyboard/toolbar support, dark mode, and active development. It requires `react-native-webview` and, for anything beyond the most basic usage, an **Expo Dev Client** (Expo Go supports only basic mode). **Recommended default editor.** Because it's WebView-based, HTML is its natural output format — a good fit for writing back to Azure DevOps' HTML-based fields, with a straightforward path to also emit/accept Markdown for orgs using that mode. ([npmjs.com/@10play/tentap-editor](https://www.npmjs.com/package/@10play/tentap-editor), [docs.expo.dev/guides/editing-richtext](https://docs.expo.dev/guides/editing-richtext/))

**Authenticated images embedded in ADO HTML:** Azure DevOps work item HTML descriptions can embed `<img>` tags pointing at attachment URLs that require an `Authorization` bearer header (ADO doesn't issue public/pre-signed URLs for attachments by default). This is directly solvable: **`expo-image`'s `source` prop accepts a `headers: Record<string,string>` field** (also exposed on `ImagePrefetchOptions.headers` for the `prefetch()` API), letting the app attach the same bearer token used for REST calls. The remaining work is **intercepting `<img>` tags during HTML rendering** (a custom renderer/tag handler in `@native-html/render`) to substitute Azure DevOps image URLs with `expo-image` components carrying the auth header, since a raw HTML `<img src>` string alone cannot carry an Authorization header. Confirmed via Expo's own docs. ([docs.expo.dev/versions/latest/sdk/image](https://docs.expo.dev/versions/latest/sdk/image/))

---

## 5. Data Layer

- **TanStack Query (React Query) v5** is the de facto standard for server-state caching in RN in 2026, including offline-first patterns. It works with any storage satisfying the AsyncStorage-like interface via **`persistQueryClient`** + a persister (`createAsyncStoragePersister`, or the newer **`experimental_createQueryPersister`** for per-query persistence rather than whole-cache blobs). Setting a persister flips `networkMode` to `'offlineFirst'` by default, so cached data renders immediately from storage even without connectivity, then revalidates in the background. ([tanstack.com/query persistQueryClient](https://tanstack.com/query/latest/docs/framework/react/plugins/persistQueryClient), [tanstack.com/query createPersister](https://tanstack.com/query/latest/docs/framework/react/plugins/createPersister))
- **`react-native-mmkv`** is the recommended fast local-storage layer: as of 2026, v4 is a **Nitro Module** — fully synchronous, JSI-backed, memory-mapped, benchmarked at roughly **30–50x faster than AsyncStorage**. It has an official React Query storage adapter (`WRAPPER_REACT_QUERY.md` in the repo) for wiring it up as the query persister's backing store. Use it for: query cache persistence, app preferences, feature flags, non-secret UI state. **Requires a dev client** (native module) — not usable in Expo Go. ([github.com/mrousavy/react-native-mmkv](https://github.com/mrousavy/react-native-mmkv/blob/main/docs/WRAPPER_REACT_QUERY.md), [pkgpulse.com storage guide](https://www.pkgpulse.com/guides/react-native-mmkv-vs-async-storage-vs-expo-secure-store-2026))
- **`expo-secure-store`** remains the right home for auth tokens, refresh tokens, and any other small secret — it's backed by iOS Keychain / Android Keystore. The 2026 community consensus pattern is explicit: **"MMKV for speed, SecureStore for secrets, AsyncStorage only for compatibility."** Practical guidance also warns against re-reading SecureStore repeatedly during render — read once at startup/session boundary and hold the token in memory (e.g., a Zustand store or React context) for the session.
- **Optimistic updates:** standard TanStack Query `onMutate`/`onError`/`onSettled` cache-patching pattern applies cleanly to ADO work item field edits, PR comment posting, and Kanban card column/state moves — update the local query cache immediately on drag/edit, roll back on API failure, reconcile with server response on success.
- **Background refresh:** see Section 7 (shared discussion with push, since both rely on `expo-background-task` behavior/limits).

---

## 6. Kanban Board UI

- **`react-native-draggable-flatlist`** (computerjazz) is the most mature RN drag-and-drop list, built on Reanimated + Gesture Handler for native 60fps interactions. However, it is architecturally a **single-list reorder** tool: its own issue tracker has long-standing open requests for **cross-list drag-and-drop** (the exact Trello/Kanban pattern needed here), and the documented workaround (`NestableDraggableFlatList` inside a shared scroll parent) is aimed at nesting draggable lists inside a scroll view, not at dragging items *between* independent horizontally-scrolling columns. ([github.com/computerjazz/react-native-draggable-flatlist issue #11](https://github.com/computerjazz/react-native-draggable-flatlist/issues/11))
- Purpose-built cross-column options exist but are all smaller/niche:
  - `react-native-dnd-board` — explicitly a Kanban board component, but built on **Reanimated v1** APIs — likely needs a compatibility check/rewrite for a New-Architecture-only, Reanimated 3/4 app.
  - `react-native-dnd` (mgcrea) — general `useDraggable`/`useDroppable` primitives on Reanimated v3, more of a toolkit than a finished board.
  - `react-native-reanimated-dnd` — newer (2.0.0 as of research), built on **Reanimated 4** + Gesture Handler, general-purpose sortable/grid/collision-detection primitives — the best-positioned *foundation* to build a custom Kanban board on top of, given it targets current Reanimated/architecture versions.
- **Recommendation:** do not expect a turnkey "RN Trello clone" library to carry this feature. Plan for **custom engineering**: horizontally-scrolling `ScrollView`/FlashList of columns, each column an internally-draggable list (reorder within column via `react-native-draggable-flatlist` or a Reanimated gesture), with cross-column drops implemented via a shared Gesture Handler pan gesture that tracks absolute position against each column's measured layout bounds (a common home-rolled pattern; `react-native-reanimated-dnd`'s droppable/collision APIs can shortcut this). Size this as a multi-week custom UI component, not a one-day integration. ([github.com/entropyconquers/react-native-reanimated-dnd](https://github.com/entropyconquers/react-native-reanimated-dnd), [npmjs.com/react-native-reanimated-dnd](https://www.npmjs.com/package/react-native-reanimated-dnd?activeTab=readme))

---

## 7. Push Notifications

Azure DevOps has **no first-party mobile push channel** — its only outbound real-time mechanism is **Service Hooks** (webhooks fired on events like work item updates, PR created/updated, build completed, etc.), configured per-project under *Project Settings → Service Hooks*, with a generic **"Web Hooks"** consumer available out of the box (alongside built-in integrations for Slack/Teams/Jenkins/etc.). There is no ADO-native way to push directly to a mobile device. ([learn.microsoft.com Service Hook Events](https://learn.microsoft.com/en-us/azure/devops/service-hooks/events?view=azure-devops), [learn.microsoft.com Webhooks](https://learn.microsoft.com/en-us/azure/devops/service-hooks/services/webhooks?view=azure-devops))

**Required architecture (small but non-optional backend):**
1. **Webhook receiver** — a small HTTPS endpoint (e.g., Azure Function / lightweight Node service) that ADO Service Hooks POST events to.
2. **Device token registry** — a datastore mapping ADO org/user identity → registered **Expo push token(s)** (`expo-notifications` obtains this token client-side; the client sends it to your backend, associated with the authenticated ADO user, on login/app start). ([docs.expo.dev/push-notifications/push-notifications-setup](https://docs.expo.dev/push-notifications/push-notifications-setup/))
3. **Fan-out** — on receiving a Service Hook event, the backend maps it to the relevant user(s) (e.g., PR reviewers, work item assignee) and calls the **Expo Push API** with their token(s).
4. Optional: event filtering/preferences (per-user notification settings) stored alongside the token registry.

This is realistically a small service (a webhook endpoint, a token table, and a call-out to Expo's push API) but is genuine backend scope for the project — it cannot be done as a pure mobile-client feature, since ADO will not push to a device directly.

**Alternative/fallback — background polling:** `expo-background-fetch` is deprecated in favor of **`expo-background-task`** (Expo SDK 53+), which uses `BGTaskScheduler` (iOS) / `WorkManager` (Android). Its limits make it unsuitable as a primary notification mechanism: **iOS does not guarantee timing** (typically 15–30 minute windows, entirely OS-scheduled, throttled by battery/network/usage conditions), the app gets only **a single worker slot** shared by all registered background tasks, and **if the user force-quits the app, iOS halts all background execution until next foreground launch**. Use background task/poll only as a best-effort supplement (e.g., silently refresh cached lists) — not as the notification delivery mechanism. **Recommendation: build the webhook+push backend; treat background polling as a minor UX nicety, not a substitute.** ([expo.dev/blog background-task](https://expo.dev/blog/goodbye-background-fetch-hello-expo-background-task), [docs.expo.dev/versions/latest/sdk/background-task](https://docs.expo.dev/versions/latest/sdk/background-task/))

---

## 8. Other Capabilities

- **Markdown editor UX for PR comments:** Given TenTap's WebView/ProseMirror foundation is heavier than needed for short PR comments, consider a lighter pattern for comment composition specifically — a plain `TextInput` with a Markdown preview toggle (using the chosen Markdown renderer to preview) may be more appropriate than embedding a full rich editor for every comment box, reserving TenTap for the heavier work-item description editing surface.
- **@mention autocomplete:** `react-native-controlled-mentions` is a small, currently-referenced library that renders formatted mention/hashtag tokens directly inside a controlled `TextInput`, with support for multiple trigger characters (e.g., `@` for people) — a reasonable low-risk choice for PR comment/work item discussion @mentions. Related options (`react-native-mentionable-textinput`, `@lowkey/react-native-mentions-input`) exist but appear smaller/less established.
- **Image picker for attachments:** `expo-image-picker` is the standard, first-party, actively maintained Expo module for photo library/camera attachment selection — low risk, Expo Go-compatible for basic use.
- **Deep links for dev.azure.com URLs:** Standard Expo pattern applies — **iOS Universal Links** via `expo.ios.associatedDomains: ["applinks:dev.azure.com"]` (plus the corresponding entitlement) and an `apple-app-site-association` file hosted at `dev.azure.com/.well-known/` — **which the app's developer does not control**, since `dev.azure.com` is Microsoft's domain. This means true Universal/App Links against `dev.azure.com` URLs are **not achievable without Microsoft's cooperation** (Microsoft would need to host the AASA/Digital Asset Links file). **Practical alternative:** register your own custom URL scheme and/or a custom short-link domain you control for in-app share links, and handle incoming `dev.azure.com` links opportunistically only where the OS offers a disambiguation/"Open in app" affordance rather than guaranteed automatic interception. Flag this constraint explicitly to stakeholders — it's a common misconception that deep-linking "into" a third-party domain is straightforward. **[unverified]** whether Microsoft publishes any AASA/assetlinks entries for `dev.azure.com` today; assume not unless confirmed. ([docs.expo.dev/linking/ios-universal-links](https://docs.expo.dev/linking/ios-universal-links/), [docs.expo.dev/linking/overview](https://docs.expo.dev/linking/overview/))
- **Biometrics:** `expo-local-authentication` (Face ID/Touch ID/Android biometric prompt) is mature and first-party — appropriate for gating app re-entry or protecting cached credentials after backgrounding.
- **File viewer for attachments:** No single first-party "universal file preview" Expo module was identified in research; the standard RN pattern is opening non-image attachments via the OS document viewer (`expo-sharing`/`Linking.openURL` on a downloaded local file, or a WebView for previewable types) rather than building custom in-app viewers for every file type. **[unverified]** — recommend prototyping with `expo-file-system` (download to cache) + `expo-sharing`/OS "Quick Look" (iOS) / Intent-based viewer (Android) rather than assuming a dedicated library exists.
- **Clipboard:** `expo-clipboard` — mature, first-party.
- **Haptics:** `expo-haptics` — mature, first-party; useful for drag-and-drop column changes and pull-to-refresh feedback.
- **Authentication (Entra ID/OAuth):** Two viable paths: (a) **`expo-auth-session`** — Expo's generic OAuth/OIDC browser-based flow, works with any standards-compliant provider including Entra ID, simplest to integrate, no native MSAL dependency; (b) native MSAL-class libraries (**`react-native-msal`**, **`react-native-app-auth`**, or a custom `react-native-azure-ad-auth`-style wrapper) for scenarios needing native broker behavior (e.g., SSO across other installed Microsoft apps, Conditional Access/Intune app-protection compliance). Microsoft's own guidance for RN apps points to `react-native-app-auth`-style OAuth2 flows and confirms Expo's `AuthSession` as a valid path when a provider-specific SDK isn't required. **Recommendation:** start with `expo-auth-session` for simplicity; escalate to native MSAL only if enterprise customers require Conditional Access/broker SSO, since that adds real dev-client native-module complexity. ([docs.expo.dev/versions/latest/sdk/auth-session](https://docs.expo.dev/versions/latest/sdk/auth-session/), [docs.expo.dev/guides/authentication](https://docs.expo.dev/guides/authentication/), Microsoft Q&A threads on RN + Entra ID)

---

## 9. App Store Considerations

- **Naming/trademark:** Azure DevOps is a Microsoft trademark. Per Microsoft's third-party trademark guidelines: **the app name may not begin with "Azure DevOps"** (or any Microsoft product name), and without a license from Microsoft, the app's name/branding/logo must be entirely your own; you *may* truthfully state compatibility/interoperability in the description. The established convention among existing third-party clients is **"\<Brand\> for Azure DevOps"** (e.g., the existing "Mobile Boards for Azure DevOps" App Store listing), paired with a visible "not affiliated with or endorsed by Microsoft" disclosure. ([microsoft.com/en-us/legal/intellectualproperty/trademarks](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks), [apps.apple.com Mobile Boards for Azure Devops](https://apps.apple.com/us/app/mobile-boards-for-azure-devops/id6768099487))
- **App review risk:** Beyond naming, standard Apple/Google review considerations apply — clear account/data-deletion path, no misleading claims of official Microsoft affiliation, and (since the app handles enterprise auth tokens and possibly biometrics) a complete, accurate privacy disclosure (App Store "Privacy Nutrition Label" / Google Play Data Safety form) matching actual data handling.
- **Privacy manifests (iOS):** Since **May 1, 2024**, Apple requires apps (and any SDKs they embed that use "required-reason" APIs) to ship a **`PrivacyInfo.xcprivacy`** file declaring `NSPrivacyTracking`, `NSPrivacyTrackingDomains`, `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes`; this remains enforced as of 2026 and App Store Connect will reject submissions missing required declarations. **Expo-specific note:** Expo SDK packages that use required-reason APIs already **ship their own bundled `PrivacyInfo` files**, but any additional third-party native modules you add (e.g., a native MSAL library, MMKV, a custom diff/highlighting native module) may need their own required-reason declarations merged in — check each native dependency and, if needed, add the aggregated required-reason usage via `app.json`/EAS config or a config plugin before submission. ([docs.expo.dev/guides/apple-privacy](https://docs.expo.dev/guides/apple-privacy/))

---

## 10. Rough Sizing

### Suggested folder/module structure (Expo Router app)

```
app/                              # Expo Router file-based routes
  (auth)/
    login.tsx
  (tabs)/
    _layout.tsx                   # bottom tabs: Boards, Work Items, PRs, Pipelines, Me
    boards/
      _layout.tsx                 # responsive master-detail wrapper (breakpoint-driven)
      index.tsx                   # Kanban board list / picker
      [boardId].tsx               # Kanban board (columns + cards)
    work-items/
      _layout.tsx
      index.tsx                   # queries / lists
      [id].tsx                    # work item detail (HTML/Markdown render + edit)
    pull-requests/
      _layout.tsx
      index.tsx
      [id]/
        _layout.tsx
        index.tsx                 # PR overview, description, reviewers
        files.tsx                 # changed files list
        diff/[filePath].tsx       # diff viewer (unified/split)
        comments.tsx
      new.tsx
    pipelines/
      index.tsx
      [id].tsx                    # run detail, stage/job logs
    settings/
      index.tsx
      notifications.tsx
      accounts.tsx
  +not-found.tsx
src/
  api/
    client.ts                     # ADO REST client (axios/fetch wrapper, auth header injection)
    workItems.ts
    pullRequests.ts
    pipelines.ts
    boards.ts
    diffs.ts                      # blob fetch + diff computation helpers (uses `diff`)
  auth/
    authSession.ts                # expo-auth-session / MSAL wrapper
    tokenStore.ts                 # expo-secure-store wrapper
  query/
    queryClient.ts                # TanStack Query client + persister (MMKV-backed)
    keys.ts                       # query key factories
    hooks/
      useWorkItem.ts
      usePullRequest.ts
      useBoard.ts
      usePipelineRuns.ts
  components/
    diff/
      DiffViewer.tsx              # FlashList-based unified/split diff renderer
      DiffLine.tsx
      SyntaxHighlightedText.tsx
    richtext/
      HtmlRenderer.tsx            # @native-html/render wrapper w/ auth-image tag handler
      MarkdownRenderer.tsx
      RichTextEditor.tsx          # TenTap wrapper
    board/
      KanbanBoard.tsx
      KanbanColumn.tsx
      KanbanCard.tsx
    mentions/
      MentionInput.tsx
    layout/
      ResponsiveSplitView.tsx     # custom master-detail (phone stack / tablet split)
      Breakpoints.ts
  notifications/
    registerForPush.ts            # expo-notifications token registration
    notificationHandlers.ts
  storage/
    mmkv.ts
    secureStore.ts
  theme/
  utils/
backend/                          # separate service, not shipped in the app bundle
  webhook-receiver/                # ADO Service Hooks HTTPS endpoint
  device-tokens/                   # token registry (DB + CRUD)
  push-dispatcher/                 # Service Hook event -> Expo Push API fan-out
app.json / app.config.ts
eas.json
```

### Top 10 dependencies (indicative versions, September 2026)

| # | Package | Indicative version | Purpose |
|---|---|---|---|
| 1 | `expo` | ~57.0.0 | SDK baseline |
| 2 | `react-native` | 0.86.x | Core runtime (bundled by Expo) |
| 3 | `expo-router` | ~7.x | File-based navigation, typed routes |
| 4 | `@tanstack/react-query` | ^5.x | Server-state cache/data layer |
| 5 | `react-native-mmkv` | ^4.x | Fast local storage (query persistence) |
| 6 | `expo-secure-store` | (SDK-bundled) | Token storage |
| 7 | `@shopify/flash-list` | ^2.x | Virtualized lists (diffs, boards, work item lists) |
| 8 | `diff` | ^5.x | Client-side Myers diff computation |
| 9 | `@native-html/render` | latest | HTML rendering (work item descriptions) |
| 10 | `@10play/tentap-editor` | latest | Rich text (HTML) editing |

*(Supporting, non-"top-10" but load-bearing: `react-native-gesture-handler`, `react-native-reanimated`, `react-native-webview`, `expo-image`, `expo-notifications`, `expo-image-picker`, `expo-local-authentication`, `expo-clipboard`, `expo-haptics`, `react-native-code-highlighter` + `react-syntax-highlighter`, `@docren/react-native-markdown` or `@ronradtke/react-native-markdown-display`, `react-native-controlled-mentions`, `expo-auth-session`.)*

---

## Citations

- Expo SDK 57 changelog — https://expo.dev/changelog/sdk-57
- Expo SDK 55 changelog — https://expo.dev/changelog/sdk-55
- Expo (@expo) on X, SDK 55 announcement — https://x.com/expo/status/2026811977990025364
- Expo New Architecture guide — https://docs.expo.dev/guides/new-architecture/
- Expo Router introduction (typed routes) — https://docs.expo.dev/router/introduction/
- Expo Router Split View (unstable, alpha) — https://docs.expo.dev/versions/latest/sdk/router/split-view/
- expo/router GitHub discussion on tablet split layouts — https://github.com/expo/router/discussions/664
- EAS usage-based pricing — https://docs.expo.dev/billing/usage-based-pricing/
- Expo Go vs Dev Client (Medium) — https://medium.com/@pamudasansika/expo-go-vs-expo-dev-client-which-one-should-you-actually-use-1538f6aae194
- Clerk: Expo Go or Development Build for auth — https://clerk.com/articles/expo-go-or-development-build-building-production-ready-authentication-with-clerk
- app.json guide (supportsTablet, orientation) — https://medium.com/@ikrammohdabdul/a-complete-go-through-on-app-json-in-react-native-expo-d0123157c8f3
- Android large screens developer guide — https://developer.android.com/guide/topics/large-screens
- Android 17 resizability mandate — https://www.buildmvpfast.com/blog/android-17-adaptive-resizability-mandate-2026
- Shopify FlashList v2 engineering post — https://shopify.engineering/flashlist-v2
- FlashList docs — https://shopify.github.io/flash-list/
- GitHub engineering: diff-line performance — https://github.blog/engineering/architecture-optimization/the-uphill-climb-of-making-diff-lines-performant/
- Azure DevOps PR Iteration Changes REST API — https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get
- `diff` (jsdiff) npm package — https://www.npmjs.com/package/diff
- react-native-shiki-engine — https://github.com/skiniks/react-native-shiki-engine
- react-shiki — https://www.npmjs.com/react-shiki
- react-native-render-html npm — https://www.npmjs.com/package/react-native-render-html
- Software Mansion (@swmansion) on X, `@native-html/render` announcement — https://x.com/swmansion/status/2028867055135432821
- native-html/render GitHub — https://github.com/native-html/render
- react-native-markdown-display "is dead" (Medium) — https://medium.com/@vishamberlal/react-native-markdown-display-is-dead-heres-what-to-use-instead-fb6924f9bb3c
- 10tap-editor / TenTap npm — https://www.npmjs.com/package/@10play/tentap-editor
- Expo editing rich text guide — https://docs.expo.dev/guides/editing-richtext/
- expo-image docs (headers support) — https://docs.expo.dev/versions/latest/sdk/image/
- TanStack Query persistQueryClient — https://tanstack.com/query/latest/docs/framework/react/plugins/persistQueryClient
- TanStack Query createPersister — https://tanstack.com/query/latest/docs/framework/react/plugins/createPersister
- react-native-mmkv React Query wrapper docs — https://github.com/mrousavy/react-native-mmkv/blob/main/docs/WRAPPER_REACT_QUERY.md
- PkgPulse: MMKV vs AsyncStorage vs SecureStore 2026 — https://www.pkgpulse.com/guides/react-native-mmkv-vs-async-storage-vs-expo-secure-store-2026
- react-native-draggable-flatlist cross-list issue #11 — https://github.com/computerjazz/react-native-draggable-flatlist/issues/11
- react-native-reanimated-dnd GitHub — https://github.com/entropyconquers/react-native-reanimated-dnd
- react-native-reanimated-dnd npm — https://www.npmjs.com/package/react-native-reanimated-dnd?activeTab=readme
- Azure DevOps Service Hook Events — https://learn.microsoft.com/en-us/azure/devops/service-hooks/events?view=azure-devops
- Azure DevOps Webhooks service hook — https://learn.microsoft.com/en-us/azure/devops/service-hooks/services/webhooks?view=azure-devops
- Expo push notifications setup — https://docs.expo.dev/push-notifications/push-notifications-setup/
- Expo blog: goodbye background-fetch, hello expo-background-task — https://expo.dev/blog/goodbye-background-fetch-hello-expo-background-task
- Expo BackgroundTask docs — https://docs.expo.dev/versions/latest/sdk/background-task/
- Expo AuthSession docs — https://docs.expo.dev/versions/latest/sdk/auth-session/
- Expo authentication guide — https://docs.expo.dev/guides/authentication/
- Expo iOS Universal Links docs — https://docs.expo.dev/linking/ios-universal-links/
- Expo linking overview — https://docs.expo.dev/linking/overview/
- Microsoft trademark and brand guidelines — https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks
- "Mobile Boards for Azure Devops" App Store listing (naming precedent) — https://apps.apple.com/us/app/mobile-boards-for-azure-devops/id6768099487
- Expo Apple privacy manifests guide — https://docs.expo.dev/guides/apple-privacy/

---

*Items marked **[unverified]** were not independently confirmed against a primary/authoritative source during this research pass and should be validated with a hands-on spike before committing engineering time.*
