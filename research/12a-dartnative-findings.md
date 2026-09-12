# DartNative — research findings

**Researched:** 2026-09-12 · **Researcher:** Claude (Opus 5) · **Status:** read-only investigation, no code changed

> **Bottom line up front.** DartNative (dartnative.com) is a six-week-old, closed-source,
> subscription-licensed mobile framework from a two-app startup. It re-implements the Flutter
> widget API on top of real UIKit / Android Views, with its own engine, its own CLI (`dn`), and
> its own package registry (dartpub.dev) — it is **not** on pub.dev and does **not** use the
> Flutter SDK. It is a different project from the older ByteDance-lineage `dart_native` FFI
> bridge (established in §1.1). Of Boardhop's 18 tracked dependencies, **at most 2 would work
> unchanged**. There is **no widget-test story at all**, **no iOS Dynamic Type**, **RTL is
> filed as broken today**, **no WebView in the widget catalog**, and **no drag-and-drop
> primitives** — which removes Boardhop's rich-text editor, its Kanban board, and its entire
> test suite. Adopting it is not a migration; it is a rewrite onto a platform with a bus factor
> of roughly one. **Recommendation: do not adopt. Revisit no earlier than mid-2027.**

---

## 1. What it is, precisely

### 1.1 It is NOT the ByteDance `dart_native` package — established explicitly

This was checked first, because the names collide. **They are two unrelated projects.**

| | **DartNative** (the subject) | **`dart_native`** (the older package) |
|---|---|---|
| Site | https://www.dartnative.com/ | — |
| GitHub | [`DartNative/dartnative`](https://github.com/DartNative/dartnative) | [`dart-native/dart_native`](https://github.com/dart-native/dart_native) |
| What it is | A **UI framework** — a Flutter-API-compatible framework rendering to native views | An **FFI / interop bridge** — call native APIs from Dart, replacing Flutter's MethodChannel |
| Owner | Presence Network Inc. (commercial) | `dart-native` GitHub org; maintainers listed as `yulingtianxia`, `Siriushe`, `hui19` |
| License | Proprietary subscription, with a BSD-3 sunset clause | BSD-3-Clause, open source |
| Stars | 98 | 963 |
| Last activity | Sep 12, 2026 (active) | `dart_native` last updated **May 21, 2024**; sibling `codegen` Aug 24, 2026 |
| pub.dev | **Not published** | `dart_native` v0.7.11, last published ~3 years ago |
| Relationship | None found | None found |

Evidence of non-relation: the `dart-native` GitHub org page lists three individual maintainers
and makes **no reference** to dartnative.com or Presence Network Inc.; conversely the
`DartNative` org has **1 public repo, 0 public members**, and describes itself as "an
independent product of Presence Network Inc." No shared contributors, no cross-links, different
licenses, different purposes.

- `yulingtianxia` (杨萧玉) is a well-known iOS engineer historically associated with ByteDance,
  and `dart_native` is widely described as originating in that orbit — but **I could not find a
  primary source on the `dart-native` GitHub org or pub.dev page stating ByteDance ownership.
  Mark the ByteDance attribution as UNVERIFIED.** It does not affect the conclusion.
- Confusingly, the **older** project also brands itself "DartNative" in its own docs, and a
  [SourceForge mirror](https://sourceforge.net/projects/dartnative.mirror/) exists under that
  name. Search results for "DartNative" mix the two freely. Treat any third-party article
  about "DartNative" dated before July 2026 as being about the **old FFI bridge**.

### 1.2 Rendering model

**Native platform views — not Skia, not Impeller.** From the README:

> "DartNative is a framework for building iOS and Android applications using Dart — with real,
> native platform UI instead of a custom rendering engine."

> "Real native views. UILabel, UITextField, UIScrollView, UITableView — not redrawn pixels."

Mechanism, per the README and site:

- Dart drives UIKit / Android View system **directly through synchronous FFI calls on the
  platform main thread** ("Zero thread hops").
- A **reconciler** diffs the widget tree and **mutates real native views in place**
  (this is what makes hot reload work — see §4).
- Layout is **Yoga** (the Facebook flexbox engine), not Flutter's own layout protocol.
- Lists use **native recycling**: `UITableView` / `RecyclerView`, exposed as `FastList` /
  `FastGrid` with a `keepAliveCount` bound.
- `CustomPaint` is re-hosted: "your `CustomPainter` paints through Core Graphics on iOS and
  `android.graphics.Canvas` on Android." A separate `dartnative_skia` plugin provides a
  `CanvasSurface` for GPU work (**Skia Graphite**) — so Skia is present as an opt-in plugin for
  canvas work, not as the UI renderer.
- Marketing claims: "0 abstraction layers", "120fps native scrolling", faster cold start
  (no renderer init), keyboard animation synced to the compositor rather than vsync.
  **None of these performance claims are independently benchmarked anywhere I could find —
  UNVERIFIED.**

### 1.3 Language and relation to Flutter

- **Language: Dart only**, for both platforms.
- **Relation: a from-scratch reimplementation of the Flutter widget *API*** — neither a fork of
  Flutter, nor a layer on top of it, but a **replacement** that deliberately preserves source
  compatibility. The site frames it as: DartNative uses the "same widgets, layout system, and
  hot reload… DartNative just renders them with the platform's real views instead of
  Impeller/Skia. **The only change is the import.**"
- The README softens this: "If you're migrating from Flutter, **most** of your widget code works
  as-is."
- Critically, **the Flutter SDK is not required and is not used.** Installation is via its own
  `dn` CLI, which "downloads the prebuilt engine (a few hundred MB) into `~/zero/bin/cache/`".
  So `flutter test`, `flutter analyze`, `flutter build`, DevTools, and every `package:flutter`
  import are outside the system. (Note the cache path `~/zero/` — suggestive of an earlier
  internal project name "zero".)

### 1.4 Who builds it, funding

- **Presence Network Inc.** — "DartNative is an independent product of Presence Network Inc."
- Founder/CEO identified in search results as **Ioseph Magno** ([@iosemagno on X](https://twitter.com/iosemagno)).
  **I could not confirm this from a primary corporate source (no about/team page found on
  dartnative.com) — mark UNVERIFIED.**
- The company's other products are the consumer apps **Presence Messenger** and **Gee AI**
  (see §3). It appears to be a small independent company, not a funded platform vendor.
- **No funding information found at all.** No VC announcement, no Crunchbase-style record
  surfaced, no employee count. **Funding: UNVERIFIED / unknown.** Revenue model is the
  subscription below plus consumer apps.
- **Team size: unknown.** The site's quantitative boast is about code, not people:
  "Half a million lines of original code", "40 repositories", "3,900 commits". A
  [ZoomInfo entry for "Presence Network Inc"](https://www.zoominfo.com/c/presence-network-inc/1335824891)
  exists but I did not verify that it refers to the same entity.

### 1.5 License — proprietary, with a sunset clause

The framework and all **first-party** plugins are **closed source**. The public GitHub repo
holds docs, tutorials, plugin examples, and the issue tracker; per the README, "the framework
itself is developed in private repositories, so the commits you see on GitHub are releases, not
day-to-day work." This explains the 98-star repo showing only **15 commits** against the site's
claim of 3,900.

The mitigation is a contractual **sunset clause** ([/license](http://www.dartnative.com/license/)),
which is genuinely better-drafted than most:

> Trigger: "(a) a formal end-of-life announcement, or (b) a continuous period of twelve (12)
> months with no updates" (absent a public maintenance statement). Remedy: publish
> "within ninety (90) days" under **BSD-3-Clause**. And: "This commitment is binding on
> Licensor's successors and assigns, survives any sale, merger, or transfer."

Also: **community** plugins are open source "always" (MIT / BSD / Apache), with every published
version archived; and **shipped apps keep working if a subscription lapses** — the subscription
gates *building and shipping*, not running.

Honest assessment of the clause: it is a real and unusually thoughtful commitment, but it is
still (a) unlitigated boilerplate from a single small company, (b) a **12-month + 90-day worst
case of ~15 months** during which a dead framework blocks your releases, and (c) a promise of
*source*, not of a *maintainer*. Half a million lines of unfamiliar engine code dropped on you
is not a rescue.

### 1.6 Pricing

| Tier | Price | Includes |
|---|---|---|
| Community | **Free** | One production app ("a production app is defined as one that has passed 1,000 installs") |
| Standard | **$49/year** | Unlimited apps; CodePush 10,000 installs/month |
| Pro | **$99/year** | Unlimited apps; CodePush 50,000 installs/month |

Plugin authors get a discount — "authors of popular plugins… pay half price… or $1 a year, based
on plugin adoption." Official demos run free with no account; your own apps need
`dn config --license-key dnk_...`, with plans picked at dartpub.dev.

The pricing is trivially cheap and **not the risk** — the risk is everything in §5. Note for
Boardhop specifically: the free tier's 1,000-install ceiling is below where a shipped free app
would land, so this is a $49–99/yr line item, which is inside the "free open-source packages are
fine" spirit of the hard rules but is still a paid dependency requiring Kelly's go-ahead.

---

## 2. Maturity

**This is the decisive section. The framework is six weeks old.**

### 2.1 Release history and cadence

The entire [changelog](http://www.dartnative.com/changelog/) has **two entries**:

| Date | Entry |
|---|---|
| **2026-07-31** | "Preview" — **"The first public preview"** |
| **2026-09-08** | "Preview" — "iOS 26 fixes: navigation bars, search bar, date picker" |

- **First release: 2026-07-31.** As of today (2026-09-12) the project is **43 days old** in public.
- **Current version: there is no semantic version.** Releases are labelled "Preview" + a date.
  There is no 1.0, no 0.x, no version to pin.
- **Cadence: two releases, ~5.5 weeks apart.** Not enough data to call a cadence.
- **Breaking-change history: effectively none, because there is no history.** The 2026-09-08
  entry says "Nothing changes in your code unless you want `onClosed` or `confirmText`."
  A 43-day-old project with no breaking changes tells you nothing about its future stability;
  it has not yet had the chance to break anything.
- **Direct contradiction to flag:** the changelog calls both releases **"Preview"**, while the
  README calls both platforms **"Production-ready"**. Those cannot both be true. Pick the
  changelog.

### 2.2 GitHub metrics ([DartNative/dartnative](https://github.com/DartNative/dartnative), read 2026-09-12)

- **Stars: 98** · **Forks: 3** · **Watchers: 0** · **Pull requests: 0**
- **Commits: 15** on main (releases only; real work is in private repos)
- **Open issues: 4 · Closed issues: 0**
- **Contributors: could not be determined** — the contributors graph had not finished computing
  when fetched. Given 15 release-only commits and 0 public org members, the public contributor
  count is near-meaningless anyway. **UNVERIFIED, but immaterial.**
- **Org: 1 public repository, 0 public members.**

All four open issues were filed by outside users within the last six days, and **none has been
closed**:

| # | Title | Author | Date | Labels |
|---|---|---|---|---|
| 12 | **TextField: no `inputFormatters`** | AbdurahmanAlmehdi | 2026-09-12 | bug, triage |
| 11 | **RTL layout does not mirror under Arabic locale** | AbdurahmanAlmehdi | 2026-09-12 | bug, triage |
| 7 | VS Code `launch.json` support with debugger & IDE hot reload | crazidev | 2026-09-07 | feature, P2, triage |
| 1 | **`dn publish` crashes on Windows** | mg3994 | 2026-09-06 | P1 |

A 0%-closed issue tracker at six weeks with a P1 open since day one is a signal about
maintainer bandwidth, not about issue quality.

### 2.3 Packages: a separate registry, not pub.dev

**DartNative is not on pub.dev, and neither are its plugins.** A pub.dev search for
"dartnative" returns 546 loosely-matching packages, of which the relevant hits are the **old**
`dart_native` (v0.7.11, ~3 years stale) and its `dart_native_gen`. **Nothing on pub.dev is the
dartnative.com framework.**

Instead there is **[dartpub.dev](https://dartpub.dev/)**, DartNative's own registry — which also
doubles as the subscription/billing portal. It hosts first-party plugins, community submissions,
and re-hosted pure-Dart packages from pub.dev.

- The site claims **34 first-party plugins**, "all free and backed by the platform's own APIs."
- Visible first-party plugins include: `dartnative_system`, `dartnative_secure_storage`,
  `dartnative_audio`, `dartnative_notifications`, `dartnative_shared_preferences`,
  `dartnative_path_provider`, `dartnative_url_launcher`, `dartnative_sqlite`,
  `dartnative_onnxruntime`, plus (per the homepage) camera, video, maps, TTS, and
  `dartnative_skia`.
- **Adoption is minuscule and measurable:** every visible package showed **weekly installs of
  54–56**. That is consistent with a few dozen people evaluating the framework. (The registry
  also rendered timestamps as "0 NaN months ago" — a live bug on the billing/registry site.)
- **Community packages: none visible in the listing.** The community tier of the ecosystem is,
  today, empty.

**The number of pub.dev packages that target DartNative is zero.** The ecosystem is a
single-vendor registry with ~34 first-party plugins and roughly 55 weekly users.

### 2.4 Boardhop's dependencies against DartNative

The rule, from the [dependencies doc](http://www.dartnative.com/docs/getting-started/dependencies/):

> **"if a package doesn't import `package:flutter`, it just works."**

Anything touching `MethodChannel` needs a port (DartNative uses FFI); anything importing
`package:flutter` — i.e. every Flutter *widget* package — needs a rewrite. Explicitly confirmed
working: "http, dio, mqtt_client, uuid, crypto, intl, collection, equatable, get_it, bloc (the
core package — `flutter_bloc` is the Flutter-bound one), solidart, logger and path".

| Boardhop dependency | Verdict | Basis |
|---|---|---|
| **dio** | ✅ **Works unchanged** | Named explicitly in the dependencies doc |
| **re_highlight** (diff engine) | ✅ Likely works | Pure Dart, no `package:flutter` import. *Inferred, not documented.* |
| **drift** | ⚠️ **Port required** | drift core is pure Dart, but its executor needs a native sqlite3. `dartnative_sqlite` exists, so a custom `QueryExecutor` is plausible — nobody has published one. Also `dart run build_runner build` should still work (pure Dart tooling). *Feasible but unbuilt.* |
| **go_router** | ❌ Port/replace | Imports `package:flutter`; built on Flutter's `Router`/`RouteInformationParser`. DartNative has its own `Navigator`/routes. Boardhop's account-scoped route table (`lib/core/routes.dart`) would be rewritten. |
| **flutter_bloc** | ❌ Port required | **Called out by name** as "the Flutter-bound one". `bloc` core works; the widget layer doesn't. |
| **html_editor_enhanced** | ❌ **No path** | A Flutter widget wrapping `flutter_inappwebview`. See WebView below. This is a settled Boardhop decision with no DartNative equivalent. |
| **flutter_inappwebview** | ❌ **Contradictory / likely absent** | The dependencies doc claims a "dartnative equivalent" for webview, but **the widget catalog lists no WebView widget at all**. Flag as unresolved; assume absent. |
| **image_picker** | ❌ Port required | MethodChannel plugin. No `dartnative_image_picker` seen; a camera plugin exists but is not the same thing. |
| **file_picker** | ❌ Port required | MethodChannel plugin; **no equivalent found**. |
| **share_plus** | ❌ Port required | MethodChannel plugin; **no equivalent found**. |
| **flutter_local_notifications** | 🔁 Replace | `dartnative_notifications` exists (local + push). Different API — rewrite, not port. |
| **url_launcher** | 🔁 Replace | `dartnative_url_launcher` exists. |
| **path_provider** | 🔁 Replace | `dartnative_path_provider` exists. |
| **shared_preferences** | 🔁 Replace | `dartnative_shared_preferences` exists. |
| **cached_network_image** | 🔁 Replace | Flutter widget. `Image.network` is native-backed with its own caching; behaviour and API differ. |
| **flutter_markdown_plus** | ❌ Port/replace | Flutter widget library built on `RichText`; **no equivalent**. |
| **flutter_widget_from_html_core** | ❌ Port/replace | Flutter widget library; **no equivalent**. This is load-bearing for ADO work-item HTML. |
| **re_editor** | ❌ Port/replace | Flutter widget, heavy `CustomPaint`/`TextPainter`; **no equivalent**. |
| **super_sliver_list** | ❌ **Replace, architecture change** | A *sliver* implementation. DartNative's sliver support is thin and its native analogue is `FastList`/`FastGrid` with a bounded `keepAliveCount`. Boardhop's diff viewer is built on it. |
| **msal_auth** (vendored, patched) | ❌ **Worst case** | A MethodChannel plugin wrapping native MSAL SDKs, of which Boardhop carries a *patched vendored copy* (`packages/msal_auth`). Would need re-writing against DartNative FFI from scratch, re-patched. Sign-in is the app's front door. |

**Tally: 1 confirmed unchanged (dio), 1 probable (re_highlight), 5 vendor-equivalent rewrites,
11 ports/rewrites with no available equivalent.**

Two additional Boardhop-specific blockers found in the widget catalog:

1. **No drag-and-drop primitives.** `LongPressDraggable` and `DragTarget` do **not** appear in
   the widget catalog. Boardhop's hand-rolled Kanban is built on exactly those two widgets
   (a settled decision). No DartNative replacement is documented.
2. **Explicitly unsupported widgets** (marked ❌ in `docs/widgets.md`): `PageView`
   ("not planned"), `NestedScrollView`, `TabBar` / `TabBarView`, `ReorderableListView`,
   `Dismissible`. Plus `Offstage` behaves differently — "the offstage child is **unmounted
   (state lost)**", which is a silent-breakage class of bug during any port.

---

## 3. Production use

**Two named apps, both belonging to the vendor. No third-party production app found. No case
studies.**

The README states the framework "is currently used in production applications including **Gee**
and **Presence Messenger**." Both are Presence Network Inc.'s own products:

| App | Store | Seller | Store listing as fetched |
|---|---|---|---|
| **Presence Messenger** | [App Store id6504456930](https://apps.apple.com/us/app/presence-messenger/id6504456930) · [Play `is.presence.app`](https://play.google.com/store/apps/details?id=is.presence.app) | Presence Network Inc. | v1.0.209 (261), iOS 16.6+, 183.7 MB, Social Networking, **1 rating** |
| **Gee AI** | [App Store id6760962082](https://apps.apple.com/us/app/gee-ai/id6760962082) · [Play `com.withgee.app`](https://play.google.com/store/apps/details?id=com.withgee.app) | Presence Network Inc. | v1.0.37+39, iOS 16.0+, 183.3 MB, Lifestyle, "hasn't received enough ratings" |

Findings and the blunt reading:

- **Both apps are first-party.** "Used in production" means "the vendor uses it for its own two
  apps." There is **no named third-party production app, anywhere.**
- **Search results describe Presence Messenger as "being ported to DartNative"** — present
  progressive. So even the flagship reference is mid-migration, not shipped.
- **I could not verify that any App Store binary post-dates DartNative's first preview
  (2026-07-31).** The listings as scraped reported last-update dates of ~March 2025 (Presence
  Messenger) and ~August 2024 (Gee AI), both *years before* the framework existed publicly.
  **However: App Store pages are JavaScript-heavy and the extracted dates were internally
  inconsistent (one version history read "March 21, 2025 back through November 13, 2025"), so
  these dates are LOW CONFIDENCE / UNVERIFIED.** What I can say firmly is: **I found no
  evidence of a store release built with DartNative.**
- **App Store review acceptance: UNVERIFIED.** No statement from the vendor about review
  outcomes, no third-party report of a DartNative app clearing review, and no verifiable
  post-preview store update. There is no *a priori* reason Apple would reject it (it is an
  AOT-compiled native binary driving UIKit, which is if anything *more* conventional than
  Flutter), and both apps' mere existence on the store shows the company can ship — but the
  specific claim "a DartNative-built binary has passed App Store review" is **not established**.
- **Corroborating adoption number:** dartpub.dev plugin installs of **54–56 per week**. Whatever
  is in production, it is not being downloaded by many developers.
- **Zero case studies, zero customer logos, zero testimonials** on the site.

---

## 4. Tooling

| Capability | Status | Detail |
|---|---|---|
| **Hot reload** | ✅ Real, and architecturally interesting | "`dn run`, edit, press `r`, see it live." The reconciler diffs widget trees and "mutates real native views in place." |
| **Hot restart** | ✅ With a nice touch | Route names are stored native-side and **replayed**, so you land back on your working screen. |
| **Logging** | ✅ | Unified log stream across Dart/native; `verbose: true` on `DartNativeLogger.run` dumps reconciler mutations. |
| **DevTools** | ❌ **Absent** | No mention anywhere in the docs. No Flutter SDK ⇒ no Flutter DevTools, no widget inspector, no timeline, no memory view. |
| **Debugger / breakpoints** | ❌ **Absent** | No documentation. Open issue [#7](https://github.com/DartNative/dartnative/issues/7) is a community *request* for "VS Code `launch.json` Support with Debugger & IDE Hot Reload" — i.e. IDE debugging does not exist yet. |
| **Widget tests** | ❌ **Nothing. At all.** | No `flutter_test` equivalent, no `dn test` command, no testing doc, no testing tutorial (all 22 tutorials checked — §4.1), no mention on the site or in search. **This is the single most disqualifying gap for Boardhop.** |
| **Unit tests** | ⚠️ Presumably `dart test` | Pure-Dart code should be testable with the standard Dart test runner. *Inferred, undocumented.* |
| **Integration tests** | ❌ Absent | No documentation. |
| **CI** | ❌ No guidance | No CI documentation. The `dn` CLI downloads a several-hundred-MB engine into `~/zero/bin/cache/` on first run and needs a license key — workable in CI but entirely undocumented, and a licensed closed-source engine in CI is its own question. |
| **CLI** | ✅ | `dn --version`, `dn doctor`, `dn create`, `dn run`, `dn publish`, `dn config --license-key`. |
| **Host OS** | ⚠️ Windows is second-class | Install is a shell script on macOS/Linux but **"manual extraction" on Windows**, and [issue #1](https://github.com/DartNative/dartnative/issues/1) — **"`dn publish` crashes on Windows", P1, open since 2026-09-06** — is unfixed. *Directly relevant: Boardhop's primary dev host is Windows 11.* |
| **Xcode / SwiftPM** | ❌ Undocumented | No Xcode or SwiftPM integration documentation found. Since DartNative ships a prebuilt engine and its own build pipeline, how a signed archive is produced, how `ExportOptions.plist`-style signing works, and whether SwiftPM dependencies can be added are all **unknown**. Boardhop's `tool/ship-ios.sh` / altool pipeline has no described analogue. |
| **iOS 26** | ✅ Explicitly targeted | The only feature release to date (2026-09-08) is seven iOS 26 fixes: nav bars during transitions, search-bar close callbacks and title position, bar-button text resizing/capsule fit, date-picker sheet layout. There is a dedicated [Liquid Glass (iOS 26)](http://www.dartnative.com/docs/platform/liquid-glass) doc, and "real liquid glass" is a headline claim — plausible, since it is the actual UIKit control. |
| **iOS 27** | ❌ **No mention** | Not in the changelog, not in the docs. iOS 27 ships this fall and is what the iPhone Duo runs. |
| **Android** | ⚠️ **SDK 36 required** | "You need the Android SDK 36 and its build-tools — `dn` refuses to build against older platforms." Material 3 + dynamic colour documented. |
| **Android 17** | ❌ **No mention** | Nothing in the changelog or docs. |
| **Foldables** | ❌ **No mention anywhere** | Not in the changelog, docs, tutorials, or site. No `displayFeatures` analogue, no hinge/posture API, no adaptive-layout guidance. |
| **Multi-window** | ❌ **No mention anywhere** | Same. |
| **iPhone Duo** | ❌ **Total silence** | See §4.2. |

### 4.1 Tutorials — what the 22 tutorials cover, and what they don't

All 22 [tutorials](http://www.dartnative.com/tutorials/) were enumerated: first app, layout,
navigation & routes, state, **porting a Flutter screen**, chat screen, photo grid, lists,
Hero story viewer, search, Liquid Glass, Material 3 & dynamic colour, native-canvas charts,
video, storage, Sign in with Apple & Google, notifications, camera, Lottie, TTS, native map,
build a plugin.

**Not one tutorial covers** testing, CI, accessibility, RTL, dynamic type, WebView, tablets,
foldables, multi-window, or adaptive layout. The curriculum is entirely
"wire up a native feature" — the cross-cutting concerns that decide whether an app is
shippable are absent. That is the tell of a very young framework.

### 4.2 What DartNative says about the iPhone Duo: **nothing**

First, verifying the device (the premise checked out):

- **Announced Wednesday 2026-09-09**, alongside iPhone 18 Pro / Pro Max
  ([Apple Newsroom](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/),
  [MacRumors](https://www.macrumors.com/2026/09/09/apple-announces-foldable-iphone-duo/),
  [TechCrunch](https://techcrunch.com/2026/09/09/apple-unveils-its-first-foldable-the-iphone-duo/)).
  **Ships 2026-10-23.** From **$1,999** ([Bloomberg](https://www.bloomberg.com/news/articles/2026-09-09/apple-s-foldable-iphone-launch-event-gets-underway)).
- **Displays:** 7.6" inner, 5.4" outer, **same aspect ratio** so content scales proportionally.
- **New UI features that matter to app developers** (per Apple's iOS 27 developer guidance as
  reported 2026-09-10, [MacRumors](https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/)):
  - **Split View on iPhone for the first time** — two apps side by side, or **two windows of
    the same app** (e.g. two Safari windows). App pairs can be saved.
    Notably, **users cannot resize the split** ([Archyde](https://www.archyde.com/iphone-duo-split-view-why-you-cant-resize-apps/)).
  - **New size-class behaviour:** inner display reports **regular × regular** (enabling
    iPad-style sidebars and multi-column layouts); outer display reports **compact horizontal ×
    regular vertical** in portrait. Apple's guidance: **stop branching on idiom or orientation,
    branch on size classes.**
  - **Chrome moves to the side** — Lock Screen controls, the Dock, and app navigation sit along
    the edge rather than the bottom, freeing vertical space.
  - Fold/occlusion geometry is exposed through **iOS 27.1 "reserved regions"** APIs.
- Developer framing in the community: "your app has **six weeks** to earn the inner screen"
  ([daily.dev issue #86](https://daily.dev/posts/issue-86-iphone-duo-is-real-and-your-app-has-six-weeks-to-earn-the-inner-screen-lvw9ejba4)).

**DartNative has said nothing about any of it.** No changelog entry, no doc, no blog, no issue.
Its one shipped feature release targets **iOS 26**, and the Duo runs **iOS 27**.

The honest counter-argument, which deserves stating: because DartNative renders **real UIKit
views inside a normal UIKit app**, a lot of Duo behaviour could come **for free** — native
`UINavigationController` chrome, native split-view participation, native size-class
propagation. A native-views framework is *structurally* better positioned for a new Apple form
factor than a framework that paints its own pixels. **But this is my inference, not a vendor
claim, and it is contradicted in practice by the fact that the framework needed seven manual
fixes just to handle iOS 26 nav bars and date pickers.** A framework that hand-patches
per-OS-version UIKit regressions will need to hand-patch the Duo too. Whether Yoga layout,
`SafeArea`, and the reconciler cope with a live fold/unfold resize and two windows of the same
app is **completely unverified — and there is no hardware, simulator guidance, or vendor
statement to verify it against.**

---

## 5. Risks

Ranked by how likely each is to end a project built on it.

1. **Bus factor ≈ 1.** This is the headline risk. Closed-source engine in private repos; a
   single small company whose day job is two consumer apps; 0 public org members; 15 public
   commits; 0 PRs; 0 issues closed. If one person stops, **you cannot fix your own framework** —
   you wait out the 12-month silence + 90-day publication window in §1.5 and then inherit half
   a million lines of someone else's engine. Compare Flutter: Google-funded, thousands of
   contributors, and you can patch the framework today (as Boardhop already does with its
   vendored `msal_auth`).
2. **No test story.** No widget tests, no integration tests, no DevTools, no IDE debugger. For
   Boardhop this is not a gap, it is a contradiction of the project's own engineering rules
   (`flutter analyze` clean and `flutter test` green before every commit). Every layout assert
   and overflow that widget tests currently catch would have to be caught by eye on a device.
3. **Community size: effectively zero.** 98 stars. 54–56 weekly plugin installs. **No Reddit
   r/FlutterDev thread found. No Hacker News thread found. No conference talk found. No
   independent blog post or review found** — repeated searches across dev.to, Medium, HN and
   Reddit returned only the vendor's own site and GitHub, plus the unrelated older
   `dart_native`. A [January 2026 Uno Platform survey of "5 best cross-platform frameworks"](https://platform.uno/articles/best-cross-platform-frameworks-2026/)
   lists Flutter, React Native, .NET MAUI, Uno and Kotlin Multiplatform — **DartNative is not
   mentioned.** When you hit a problem, **there is no Stack Overflow answer and no one to ask
   but the vendor.**
4. **Right-to-left is broken right now.** The docs promise full RTL — `Directionality.of`
   "works everywhere", `EdgeInsetsDirectional`/`AlignmentDirectional` resolve, `Row`/`Column`/
   `Wrap` "mirror on their own under right-to-left". But
   [issue #11](https://github.com/DartNative/dartnative/issues/11), filed **today**:
   **"RTL layout does not mirror under Arabic locale."** Docs describe intent; the tracker
   describes reality. Treat every other documented capability with the same suspicion.
5. **iOS Dynamic Type is not supported.** The widget catalog states text uses platform
   conventions: **UIKit points on iOS (fixed size)** versus **SP on Android (scales with
   accessibility settings)**. So Android honours the user's font-size setting and **iOS does
   not**. That is an accessibility regression against Flutter (which scales via
   `TextScaler`) and against native SwiftUI/UIKit apps, and it breaks Boardhop's existing
   `xcrun simctl ui <udid> content_size` review step.
6. **Accessibility more broadly: undocumented.** `docs/widgets.md` has **no `Semantics` widget,
   no accessibility section, no VoiceOver/TalkBack guidance**. Some accessibility comes free
   from using real `UILabel`/`UIButton` — that is a genuine structural advantage over a
   pixel-painting renderer — but custom widgets, semantic grouping, labels, traits, and
   announcements have **no documented API at all**. For an app aiming at the App Store this is
   an unquantified liability. **UNVERIFIED whether any semantics API exists.**
7. **WebView / platform views: contradictory, likely absent.** The dependencies doc implies a
   "dartnative equivalent" for webview; the widget catalog lists **no WebView widget**. For
   Boardhop this is fatal on its own — `html_editor_enhanced` (a settled decision) is a
   WebView-based rich-text editor, and work-item HTML rendering depends on the HTML stack.
   There is also the deeper irony: **DartNative has no "platform view" concept, because
   everything is a platform view** — which is elegant until you need to embed something
   DartNative hasn't wrapped, at which point there is no documented escape hatch equivalent to
   Flutter's `UiKitView`/`AndroidView`.
8. **Docs quality: good prose, thin coverage, and already drifting.** What exists is
   well-written and unusually candid (explicit ❌ markers for unsupported widgets, an honest
   `Offstage` caveat). But the widget overview page is "a landing stub… synced from the
   framework's `widgets.md` at build time"; there are no API reference docs; and the
   docs-vs-tracker contradiction on RTL plus the "Preview"-vs-"Production-ready" contradiction
   show the docs running ahead of the code.
9. **Windows tooling is broken.** `dn publish` crashes on Windows (P1, open). Boardhop's
   primary host is Windows 11.
10. **Ecosystem lock-in via a private registry.** Dependencies come from **dartpub.dev**, which
    is also the billing system. You are not just adopting a framework; you are adopting one
    vendor's package registry, with no community packages in it yet, as a hard dependency of
    your build.
11. **Unverifiable performance claims.** "120fps native scrolling", "0 abstraction layers",
    faster cold start. No independent benchmark exists. The *architecture* makes the scrolling
    claim plausible (it is a real `UITableView`), but nothing is measured.
12. **Single-threaded-by-design main thread.** "All Dart code runs on the platform's main
    thread." This is sold as eliminating thread hops, and for UI mutation it does. But it means
    **your Dart work is on the UI thread** — for Boardhop, that includes Myers diff over large
    files and JSON decoding of big work-item payloads. Flutter's UI-thread isolate plus
    `compute()`/isolates is the established escape; whether DartNative offers an equivalent is
    **undocumented and unverified**. Potential jank risk exactly where Boardhop is heaviest.

---

## 6. Contrast with Flutter's own roadmap

### 6.1 Where Flutter actually is (verified)

- **[Flutter & Dart's 2026 roadmap](https://flutter.dev/blog/flutter-darts-2026-roadmap)
  (published 2026-02-24):** commits to *"ensuring day-zero support for Android 17 and upcoming
  iOS releases, alongside multi-window support for desktop where our partners at Canonical
  continue to make progress."* **Foldables, iPhone Duo, and adaptive layout are not mentioned
  in the roadmap at all** — unsurprising, since it predates the Duo's announcement by six
  months.
- **[Flutter 3.47](https://flutter.dev/blog/whats-new-in-flutter-3-47) (published 2026-08-12):**
  - **Multi-window is desktop-only and still experimental.** "In partnership with Canonical…
    we are expanding our experimental desktop windowing APIs. **Linux and Windows now support
    popup windows**", plus `windowHandle` access (`HWND`/`NSWindow`/`GtkWindow`) and a
    sized-to-content API. Nothing for mobile.
  - **Apple readiness is explicit:** "With **Xcode 27, iOS 27, and macOS 27** arriving this
    fall, we have focused heavily on making sure Flutter is ready for the upcoming updates."
  - **Minimum versions rose:** iOS 13 → **15**, macOS 10.15 → **12**.
  - Also: `material_ui` / `cupertino_ui` 1.0 as standalone packages (design systems decoupled
    from the SDK), Impeller on by default for macOS/Windows/Linux, **Widget Previews stable**,
    flavors on Windows/Linux, Dart 3.13.
  - **No mention of foldables, iPhone Duo, or display features.**
- **[Multi-Window Pre-launch Checklist, flutter/flutter#177586](https://github.com/flutter/flutter/issues/177586)**
  (opened 2025-10-27, assigned to `mattkae`): **open, 0 of 20 items complete**, feature still
  behind a flag. So desktop multi-window is not close to stable, and mobile multi-window is not
  even on this list. Related umbrella:
  [#142845 "Multi View for Windows/MacOS"](https://github.com/flutter/flutter/issues/142845).
- **iPhone Duo specifically:**
  [**flutter/flutter#192515** — "Proposal: populate `MediaQuery.displayFeatures` on iOS for
  iPhone Duo (foldable)"](https://github.com/flutter/flutter/issues/192515), opened
  **2026-09-09** (announcement day) by community member `mirzaaghazadeh`. **Status: open, no
  assignee, labels P2 / c: proposal / engine / platform-ios / team-ios, no team timeline.**
  The proposal's own words: *"Flutter apps run on it today, but they have **no fold awareness at
  all**: `DisplayFeature` is documented as 'populated only on Android.'"* It asks for iOS 27.1
  reserved-region APIs to be wired into the Darwin embedder.
- **Third-party summary** ([iPhone Duo Support: Flutter](https://iphoneduosupport.com/frameworks/flutter/),
  verified 2026-09-09): *"Flutter has not shipped iPhone Duo support or published guidance for
  it."* Whether the iOS embedder populates `displayFeatures` from `reservedRegions` "is not
  something we can confirm" — **assume `displayFeatures` is empty on iPhone Duo** until
  verified on hardware. Practical advice today: `MediaQuery.sizeOf(context)`, `LayoutBuilder`,
  treat left/right padding as distinct, drop orientation locks, rebuild against the iOS 27.1
  SDK.

### 6.2 Head to head

| | **Flutter 3.47** | **DartNative (Preview 2026-09-08)** |
|---|---|---|
| Age / maturity | 2017 →; stable, versioned, 3.47 | **43 days public**; two "Preview" builds, no version numbers |
| Source | Open, BSD-3 — patch it yourself today | Closed; BSD-3 only on a 12-month+90-day death trigger |
| Backing | Google + Canonical + thousands of contributors | One small company, bus factor ≈ 1 |
| iOS 27 / Xcode 27 | **Explicitly prepared** (3.47, Aug 2026) | **No mention**; targets iOS 26 |
| Android 17 | **Day-zero commitment** (2026 roadmap) | No mention; requires Android SDK 36 |
| Mobile multi-window | **Not supported** | **Not supported / not mentioned** |
| Desktop multi-window | Experimental, behind a flag, 0/20 checklist | N/A (mobile only) |
| Foldable awareness | `MediaQuery.displayFeatures` — **Android only**; iOS is an open P2 proposal (#192515) | **Nothing at all** |
| iPhone Duo | No shipped support, **but a public proposal, a tracked issue, a stated day-zero-Apple posture, and third-party guidance within 24h** | **Total silence** |
| Duo size classes / sidebars | Works via `MediaQuery`/`LayoutBuilder` today; adaptive widgets exist | Untested; **no adaptive-layout guidance and no `TabBar`/`PageView`** |
| Duo chrome (side bars, split view) | Flutter paints its own chrome ⇒ must reimplement Apple's new layout | **Real UIKit chrome ⇒ plausibly free** (inference, unverified) |
| Testing | `flutter_test`, integration_test, Widget Previews stable, DevTools | **None** |

**The honest verdict on the foldable question — which is the one place DartNative could have
won.** Neither framework supports the iPhone Duo today. Flutter's gap is *specific and
tracked*: `DisplayFeature` is Android-only, and issue #192515 names exactly the API that must
be wired up. Everything else about the Duo — size classes, sidebars, split-view participation —
Flutter already handles through `MediaQuery`/`LayoutBuilder`, and Flutter has publicly committed
to day-zero support for upcoming iOS releases. DartNative's architecture is arguably *better
suited* to the Duo in principle (real UIKit inherits Apple's new chrome and size-class
behaviour for free), **but it has published nothing, tested nothing, and its only release to
date was seven hand-patches for iOS 26 nav bars — while the Duo ships on iOS 27 in six weeks.**
A theoretical advantage from a vendor that has not mentioned the device is worth less than a
tracked gap in a framework with a thousand contributors.

---

## 7. Recommendation for Boardhop

**Do not adopt. Do not prototype. Revisit no earlier than mid-2027, gated on the checkpoints below.**

Reasoning specific to this codebase, not generic caution:

- **It is a rewrite, not a migration.** 16 of 18 tracked dependencies need porting or
  replacement, including the three settled architectural decisions: `html_editor_enhanced`
  (no WebView), the hand-rolled Kanban (**no `LongPressDraggable`/`DragTarget`**), and the diff
  viewer's `super_sliver_list` (no slivers; `FastList` instead). `msal_auth` — already a
  *patched vendored* plugin — would be rebuilt from scratch against an undocumented FFI surface,
  and sign-in is the app's only door.
- **It would delete the safety net.** No widget tests, no DevTools, no IDE debugger. Boardhop's
  rules require `flutter analyze` clean and `flutter test` green before every commit, and its
  iOS review process depends on debug-build asserts and layout-overflow detection — which is
  precisely how the go_router assert and the Row overflow were found. DartNative offers no
  substitute for any of that.
- **The Windows host is broken** (`dn publish`, P1 open), and the iOS ship path
  (`tool/ship-ios.sh`, `ExportOptions.plist`, altool) has no documented DartNative analogue —
  no Xcode/SwiftPM integration docs exist.
- **Accessibility would regress**, measurably: **no iOS Dynamic Type** (fixed UIKit points),
  no documented `Semantics` API, and RTL filed as broken today.
- **The foldable argument does not rescue it.** If the Duo is the motivation, the cheap move is
  to make Boardhop's existing Flutter layouts Duo-ready now — it already uses `Breakpoint` and
  checks compact/expanded widths, which is exactly Apple's "branch on size classes, not idiom"
  guidance. Watch [flutter/flutter#192515](https://github.com/flutter/flutter/issues/192515),
  rebuild against the iOS 27.1 SDK, and assume `displayFeatures` is empty. That is days of
  work against a rewrite.

**What genuinely commends it** (stated so this isn't a hatchet job): the architecture is the
right idea — real UIKit text, scrolling, keyboard and Liquid Glass, native list recycling, a
reconciler that mutates native views in place while keeping hot reload, and route-replaying hot
restart. The sunset clause is a more serious continuity commitment than most commercial
frameworks offer. The docs are candid about what is unsupported. If it is still maintained in
2027 with a real test story, it deserves another look.

**Revisit checkpoints — all of these before reconsidering:**

1. A **versioned stable release** (not "Preview"), plus 12+ months of changelog.
2. A **widget/integration test framework** and IDE debugging.
3. **A named third-party production app** — not Presence Messenger or Gee.
4. **iOS Dynamic Type**, a documented `Semantics` API, and issue #11 (RTL) closed.
5. **A WebView** and a documented escape hatch for unwrapped native views.
6. **More than one visible maintainer**, or the engine open-sourced ahead of the sunset trigger.
7. Community traction above noise: >1,000 stars, community plugins in dartpub.dev, and at least
   one independent technical review.

---

## Sources

All URLs fetched or searched on **2026-09-12** unless noted.

**DartNative — primary (vendor)**

- https://www.dartnative.com/ — homepage: rendering claims, pricing, plugin ecosystem, LOC/repo/commit claims
- http://www.dartnative.com/changelog/ — full changelog (two entries: 2026-07-31, 2026-09-08)
- http://www.dartnative.com/license/ — proprietary license and sunset clause
- http://www.dartnative.com/docs/ — documentation index
- http://www.dartnative.com/docs/getting-started/installation/ — `dn` CLI, Android SDK 36, hosts, license key, engine cache
- http://www.dartnative.com/docs/getting-started/dependencies/ — pub.dev compatibility rule, working packages
- http://www.dartnative.com/docs/widgets/overview/ — widget overview stub
- http://www.dartnative.com/docs/debugging/hot-reload/ — hot reload/restart, logging
- http://www.dartnative.com/docs/platform/liquid-glass — Liquid Glass (iOS 26)
- http://www.dartnative.com/docs/platform/material-3 — Material 3 (Android)
- http://www.dartnative.com/tutorials/ — all 22 tutorials
- https://dartpub.dev/ — private package registry, first-party plugins, install counts

**DartNative — GitHub**

- https://github.com/DartNative/dartnative — 98★, 3 forks, 15 commits, 4 open issues
- https://github.com/DartNative/dartnative/blob/main/README.md — "Production-ready", Yoga, Skia Graphite, Gee/Presence Messenger, private repos
- https://github.com/DartNative/dartnative/blob/main/docs/widgets.md — widget catalog, RTL claims, Dynamic Type, CustomPaint, unsupported widgets
- https://github.com/DartNative/dartnative/issues — issue list
- https://github.com/DartNative/dartnative/issues/1 — `dn publish` crashes on Windows (P1, open)
- https://github.com/DartNative/dartnative/issues/7 — VS Code debugger / IDE hot reload request
- https://github.com/DartNative/dartnative/issues/11 — RTL does not mirror under Arabic locale
- https://github.com/DartNative/dartnative/issues/12 — TextField missing `inputFormatters`
- https://github.com/DartNative — org: 1 public repo, 0 public members
- https://github.com/DartNative/dartnative/graphs/contributors — *not resolvable (graph still computing)*

**The other `dart_native` (disambiguation)**

- https://github.com/dart-native/dart_native — 963★, BSD-3, FFI bridge, last updated 2024-05-21
- https://github.com/dart-native — org members `yulingtianxia`/`Siriushe`/`hui19`; `codegen`, `ffi_log`
- https://github.com/yulingtianxia — maintainer profile
- https://pub.dev/packages?q=dartnative — 546 results; `dart_native` v0.7.11 (~3y); framework absent
- https://sourceforge.net/projects/dartnative.mirror/ — mirror of the older project
- https://deepwiki.com/dart-native/dart_native — third-party overview

**Production use**

- https://apps.apple.com/us/app/presence-messenger/id6504456930 — Presence Network Inc., 1 rating (dates low-confidence)
- https://play.google.com/store/apps/details?id=is.presence.app — Presence Messenger, Android
- https://apps.apple.com/us/app/gee-ai/id6760962082 — Gee AI, Presence Network Inc. (dates low-confidence)
- https://play.google.com/store/apps/details?id=com.withgee.app — Gee, Android
- https://twitter.com/iosemagno — founder attribution (unverified)
- https://www.zoominfo.com/c/presence-network-inc/1335824891 — company record (unverified identity)

**Flutter roadmap and releases**

- https://flutter.dev/blog/flutter-darts-2026-roadmap — 2026-02-24; Android 17 day-zero, desktop multi-window
- https://flutter.dev/blog/whats-new-in-flutter-3-47 — 2026-08-12; Xcode/iOS/macOS 27 readiness, desktop popups, min iOS 15
- https://docs.flutter.dev/release/release-notes/release-notes-3.47.0 — 3.47.0 release notes
- https://flutter.dev/blog/whats-new-in-flutter-3-44 — earlier multi-window preview, Canonical lead maintainer
- https://github.com/flutter/flutter/issues/192515 — **Proposal: populate `displayFeatures` on iOS for iPhone Duo** (opened 2026-09-09, open, P2)
- https://github.com/flutter/flutter/issues/177586 — Multi-Window Pre-launch Checklist (0/20, behind flag)
- https://github.com/flutter/flutter/issues/142845 — Multi View for Windows/macOS umbrella
- https://github.com/flutter/flutter/issues/170310 — iOS 26 Liquid Glass in Cupertino widgets
- https://iphoneduosupport.com/frameworks/flutter/ — "Flutter has not shipped iPhone Duo support" (verified 2026-09-09)
- https://docs.flutter.dev/add-to-app/multiple-flutters — multiple Flutter views

**iPhone Duo (device verification)**

- https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/ — announcement, 2026-09-09
- https://www.macrumors.com/2026/09/09/apple-announces-foldable-iphone-duo/ — announcement
- https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/ — iOS 27 size classes, side chrome
- https://techcrunch.com/2026/09/09/apple-unveils-its-first-foldable-the-iphone-duo/ — announcement
- https://www.bloomberg.com/news/articles/2026-09-09/apple-s-foldable-iphone-launch-event-gets-underway — $1,999
- https://www.cnn.com/2026/09/09/tech/apple-announces-iphone-duo-first-foldable-iphone — hands-on
- https://en.wikipedia.org/wiki/IPhone_Duo — specs summary
- https://www.theapplepost.com/2026/09/09/71990/iphone-duo-brings-split-view-multitasking-to-iphone-for-the-first-time/ — Split View
- https://techmymoney.com/2026/09/09/iphone-duo-interface-ipad-style-sidebars-split-view-and-dual-screen-camera-tricks/ — sidebars
- https://www.archyde.com/iphone-duo-split-view-why-you-cant-resize-apps/ — non-resizable split
- https://iphoneduo.dev/blog/01-prepare-your-app-for-iphone-duo — size-class guidance
- https://daily.dev/posts/issue-86-iphone-duo-is-real-and-your-app-has-six-weeks-to-earn-the-inner-screen-lvw9ejba4 — developer framing
- https://dev.to/navid_mirzaaghazadeh_e775/what-actually-changes-in-your-ios-app-for-iphone-duo-11fo — code-level changes
- https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5 — Swift changes
- https://github.com/mirzaaghazadeh/iphone-duo-skills — community Duo guidance

**Third-party coverage (searched, and the negative result)**

- https://platform.uno/articles/best-cross-platform-frameworks-2026/ — 2026-01-14; lists Flutter, React Native, MAUI, Uno, KMP — **DartNative absent**
- https://medium.com/@syxiajia/dartnative-in-harmonyos-next-6591d2b12a48 — about the **older** `dart_native`, June 2025
- Searches returning **no DartNative coverage**: r/FlutterDev / Reddit; Hacker News; dev.to and Medium (Jul–Aug 2026); "built with DartNative"; conference talks; accessibility/RTL/testing. **No independent technical review of dartnative.com exists as of 2026-09-12.**

---

## Explicitly unverified

Listed so nothing above is mistaken for a checked fact.

1. **ByteDance's ownership of the older `dart_native`** — widely believed, no primary source found. Immaterial to conclusions.
2. **Ioseph Magno as founder/CEO of Presence Network Inc.** — from search results only; no about/team page on dartnative.com.
3. **Funding, revenue, headcount of Presence Network Inc.** — nothing found.
4. **Contributor count** for `DartNative/dartnative` — graph would not resolve.
5. **App Store last-update dates** for Presence Messenger and Gee AI — scraped dates were internally inconsistent and predate the framework's public preview; treat as low confidence. The firm finding is only that **no DartNative-built store release could be confirmed**.
6. **App Store review acceptance of a DartNative binary** — no vendor statement, no third-party report.
7. **All performance claims** — 120fps scrolling, cold-start advantage, keyboard sync. No independent benchmark.
8. **Whether any `Semantics`/accessibility API exists** — absent from docs; absence of documentation is not proof of absence of API.
9. **WebView availability** — dependencies doc and widget catalog contradict each other.
10. **Whether `LongPressDraggable`/`DragTarget` exist** — not in the catalog; not stated as unsupported either.
11. **Isolate / background-work support** — undocumented; the main-thread jank risk is inferred from the "all Dart on the main thread" design, not measured.
12. **Xcode/SwiftPM integration and the signed-archive path** — no documentation found.
13. **Whether Duo behaviour (fold resize, two windows of one app, regular×regular size classes) works via native views** — plausible by architecture, entirely untested, no vendor statement.
14. **Real-world install/adoption numbers** — inferred from dartpub.dev's 54–56 weekly plugin installs.
