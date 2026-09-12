# 12b — iPhone Duo and Flutter

**Date:** 2026-09-12. Web research only; no code was changed. Every claim below carries a source URL and, where the source is dated, its date. Claims that could not be confirmed against a primary source are marked **unverified**. Nothing here has been run on hardware: the device and the OS it needs both ship **2026-10-23**, six weeks from now, and the SDK that targets it was not yet downloadable on the day this was written.

**Standing caveat for the whole document.** Apple announced iPhone Duo on 2026-09-09. Xcode 27.1 beta — the first toolchain with the iPhone Duo SDK and simulator — is listed by Apple as "coming later this month" and was **not available on 2026-09-12** ([developer.apple.com/iphone-duo](https://developer.apple.com/iphone-duo/), fetched 2026-09-12). So every developer-facing statement in the press, including the well-argued ones, is a reading of Apple's Tech Talk videos rather than something anyone has compiled. Treat API spellings as provisional.

---

## Executive summary

1. **The product is real and the name is confirmed: "iPhone Duo."** Announced 2026-09-09, pre-orders 2026-10-16, on sale 2026-10-23, from $1,999. 5.4-inch outer display, 7.6-inch inner display. It ships on **iOS 27.1**, not iOS 26.x — the premise in the brief that this is an iOS 26.x feature set is wrong, and the version gap matters because the app-compatibility tiers are keyed to the SDK version.
2. **This is the first iPhone with Split View and with multiple windows of one app.** The split is a **fixed 50/50** with no draggable divider, and each half is roughly the size of the outer display. There is **no Stage Manager** on iPhone Duo (unannounced; see caveat below).
3. **Apps that are not rebuilt still run.** Apple has a three-tier compatibility ladder — pre-iOS 27 SDK apps are letterboxed on a black background, iOS 27 SDK apps get more of the screen, iOS 27.1 SDK apps go edge to edge. **No deadline and no App Store requirement has been announced** by anyone.
4. **Flutter has shipped nothing for this.** Flutter's only foldable abstraction, `MediaQuery.displayFeatures`, is documented as "populated only on Android"; the multi-window work is desktop-only, `@internal`, and behind a main-channel flag; `dual_screen`/`TwoPane` has not been published in about three years and is Android-only by its own description. A proposal to bridge iOS reserved regions into `displayFeatures` was filed by a community member on the announcement day and has no maintainer response.
5. **Flutter is not, however, broken on the device.** Flutter 3.47 (2026-08-12) already did the one thing that was mandatory: it migrated apps to the `UIScene` lifecycle that the iOS 27 SDK requires, and raised the minimum iOS target to 15. Boardhop's `Info.plist` already carries the scene manifest. What Flutter lacks is the *opt-in* surface — reserved regions, arrangements, vertical bars, hinge angle, extra scenes — not the ability to launch.
6. **For Boardhop specifically, the news is mostly good and the work is mostly not Flutter's to do.** The app is already responsive with three breakpoints, already uses `SafeArea` per edge with no symmetric-inset arithmetic anywhere, and already has tablet layouts that the inner display will select. Three concrete things need attention: the `SideBySide` two-column threshold misses the inner display by 57 pt, `display_cutout.dart` asks iOS for an interface orientation that Apple says the inner display does not honour, and the `html_editor_enhanced` WebView is the piece most likely to misbehave under live resize.
7. **Every other cross-platform framework is in the same place or worse.** React Native, .NET MAUI and Compose Multiplatform have made **no official statement at all**, and none has a fold API on iOS. Flutter is not behind its peers here; the whole category is behind.

---

## Part 1 — The device and the OS

### 1.1 Product, dates, price

| Fact | Value | Source |
|---|---|---|
| Name | **iPhone Duo** | [Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) |
| Announced | 2026-09-09, at Apple's "Surprise and Shine" event in Cupertino | [Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/); [TechCrunch, 2026-09-09](https://techcrunch.com/2026/09/09/apple-unveils-its-first-foldable-the-iphone-duo/) |
| Pre-orders | Friday 2026-10-16, 5 a.m. PT | [Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) |
| On sale | Friday 2026-10-23, in more than 70 countries and regions | [Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) |
| Price | From $1,999 | [Engadget, 2026-09-09](https://www.engadget.com/2254027/apple-iphone-duo-announced-specs-price/) |
| Announced alongside | iPhone 18 Pro and iPhone 18 Pro Max; first marquee device under CEO John Ternus | [NBC News, 2026-09-09](https://www.nbcnews.com/tech/apple/apple-foldable-phone-new-fold-18-launch-ceo-john-ternus-rcna596652) |
| Form factor | Book-style fold; "about the size of a passport when closed"; thinnest iPhone yet at 0.21 in / 5.2 mm open; hinge of over 100 components with a custom torque profile | [Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/); [Engadget, 2026-09-09](https://www.engadget.com/2253955/everything-apple-announced-at-the-foldable-iphone-launch/) |

Note on the name: "iPhone Duo" is the shipping name. Pre-announcement coverage used "iPhone Fold" and "iPhone Ultra" ([GSMArena](https://m.gsmarena.com/iphone_fold_screen_sizes_outed-news-68771.php); [Macworld](https://www.macworld.com/article/2629813/iphone-ultra-folding-design-display-specs-release.html)); those names are obsolete.

### 1.2 Displays — pixels, points, aspect ratios

From Apple's own technical specifications page ([apple.com/iphone-duo/specs](https://www.apple.com/iphone-duo/specs/), fetched 2026-09-12):

| | Inner display | Outer display |
|---|---|---|
| Diagonal | 7.6 in, all-screen OLED folding | 5.4 in, all-screen OLED |
| Pixels | 1878 × 2670 | 1398 × 2034 |
| Density | 430 ppi | 460 ppi |
| Both | Super Retina XDR, ProMotion, Always On, 3000 nits peak | same |

Device dimensions, same source: **unfolded** 164.6 × 117.8 × 5.2 mm; **folded** 84.1 × 117.8 × 11.3 mm. So the device is *wider than it is tall* when open — the inner display's long edge is horizontal in the natural open pose.

**Logical sizes in points** (this is the number that matters for `MediaQuery`):

| | Points | Aspect ratio (long : short) | Scale |
|---|---|---|---|
| Inner | **669 × 951 pt** | 1.4215 : 1 | 3× rendered, downsampled (2007 × 2853 → 1878 × 2670) |
| Outer | **466 × 678 pt** | 1.4549 : 1 | true 3× (466 × 3 = 1398, 678 × 3 = 2034) |

Source for the point sizes: [blakecrosley.com, "iPhone Duo for Developers: The 1.42 Problem and the SDK Gap", 2026-09-09](https://blakecrosley.com/blog/iphone-duo-for-developers), corroborated by [MacObserver, "iPhone Duo Display Resolutions Explained"](https://www.macobserver.com/tips/round-ups/iphone-duo-display-resolutions-explained-1878-x-2670-inside-1398-x-2034-outside-aspect-rat/). **Partly unverified:** Apple has not published point sizes, and the inner figure requires a downsampled 3× render (like the old iPhone Plus models) rather than a clean 3× divide — 1878 / 3 = 626, not 669. The arithmetic is self-consistent (1878 / 669 = 2.807 and 2670 / 951 = 2.808, the same factor on both axes, and 951 / 669 = 1.4215 matches the reported 1.42), so the claim hangs together, but it is a blog's inference and should be confirmed against the Xcode 27.1 simulator when it lands.

**Aspect ratio discrepancy worth knowing about.** Apple's newsroom copy says "both displays share the same aspect ratio" ([Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/)), and MacObserver's headline repeats it. The published pixel counts give 1.4215 for the inner and 1.4549 for the outer — close, and close enough for marketing, but **not identical** (a 2.3 percent difference). Do not write layout code that assumes a half of the inner display is pixel-identical to the outer display.

**The "1.42 problem."** The inner display's ratio is within half a percent of √2 (1.4142), the A-paper ratio. That is excellent for documents, feeds and two-pane layouts and poor for 16:9 video: a 16:9 frame renders at 951 × 535 pt, leaving about 134 pt of letterbox split above and below — a fifth of the screen ([blakecrosley.com, 2026-09-09](https://blakecrosley.com/blog/iphone-duo-for-developers)). For Boardhop, which shows lists, forms, diffs and code, the ratio is a gift rather than a problem.

### 1.3 Postures

Apple's hinge API reports three coarse states plus a continuous angle: **closed, partially open, fully open** ([Apple, "Leverage multiple displays and scenes on iPhone Duo", Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/)). The adaptive-layout talk additionally describes a *flat* case (hinge division region has zero width), a *book* case (partially folded, held like a book) and a *tent* case (propped on a table), and gives different guidance for each ([Apple, Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/)).

A commonly cited list of "five named poses" — StandBy, Landscape, Portrait, Seated, Standing — comes from [MacObserver, 2026-09-12](https://www.macobserver.com/news/iphone-duo-posable-positions-rebuilt-standby-what-apple-documents/). That article mixes a software mode (StandBy) and two orientations in with two hinge positions, and the same article concedes Apple "publishes no hinge-state sensor of any kind" and no angle ranges. **Treat the five-pose list as unverified journalism**; the three hinge states from the Tech Talk are the API-level truth.

For app layout, Apple's instruction is blunt: the device has **four layout situations** an app must handle — closed portrait, closed landscape, open tall, open wide ([dev.to, arshtechpro, 2026-09-09](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5)) — and hinge data must **not** be used to make layout decisions ([Apple, Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/), explicit: "hinge data is for interactions and effects; use layout APIs for arrangement decisions").

### 1.4 Size classes

From [Apple, "Prepare your app for iPhone Duo", Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/):

- **Outer display:** behaves like any other iPhone — compact horizontal in portrait, compact in both dimensions in landscape.
- **Inner display:** **regular in both dimensions**, in every orientation, "to leave room for sidebars." It is iPad-shaped for layout purposes.
- Critically: "the inner display **doesn't honor supported interface orientations**, so use size classes rather than orientation."

`UIScreen.main` is called out as ambiguous on a two-display device and is "heading for deprecation"; the replacement is `window?.windowScene?.screen` ([Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/); restated in [dev.to, arshtechpro, 2026-09-09](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5)).

### 1.5 Split View, multi-window and Stage Manager

**Split View is new to iPhone with this device.** Two apps side by side, or two windows of the same app such as Safari, with the ability to save app pairs and swap between them ([Apple Newsroom, 2026-09-09](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/)).

**The split is fixed 50/50 with no draggable divider.** [MacRumors, 2026-09-11](https://www.macrumors.com/2026/09/11/iphone-duo-split-view-not-like-ipad/): "If you put two apps side by side on the iPhone Duo's 7.6-inch foldable display, you can't drag the divider between them to make one app take up more space than the other. It's a fixed 50/50 split, regardless." Each half is roughly the dimensions of the outer screen, with the divider sitting on the fold line. Split View works in both landscape and portrait on the inner display. The stated rationale is exactly the developer-facing one: a draggable divider would produce window sizes that match neither display and would widen the support burden.

> **Conflicting source, flagged.** A secondary summary ([techmymoney, 2026-09-09](https://techmymoney.com/2026/09/09/iphone-duo-interface-ipad-style-sidebars-split-view-and-dual-screen-camera-tricks/)) claims "users can drag the central boundary to allocate more screen area to either active application window." MacRumors' dedicated 2026-09-11 article is more specific, later, and consistent with Apple's aspect-ratio rationale. Going with fixed 50/50; **re-verify in the simulator**, because a resizable divider would change the breakpoint analysis in Part 3 materially.

So each Split View pane is approximately **475 × 669 pt** (951 / 2 ≈ 475.5, close to the outer display's 466). **Unverified:** whether iOS reports a pane as compact or regular horizontal. Apple says the inner *display* is regular/regular; a 475 pt pane is narrower than any regular-width iPad pane, so compact is the likely report, but no source states it.

**Multiple scenes.** iPhone Duo is the first iPhone to support multiple instances of an app's UI. Apps that already support multiple scenes on iPad work here with no extra work; the system manages the lifecycle, and `UIWindowSceneActivation` is the normal way to request a new one. **New windows can only be created on the inner display**; the outer display is reserved for supplementary content. Apps must handle scene-creation failure gracefully. ([Apple, Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/))

**Scene accessories** are a new mechanism for putting supplementary UI on the second display simultaneously — the headline case is `CameraCaptureAccessory`, which shows content on the outer display to the person being photographed while the photographer uses the inner display. Availability is system-controlled and must be observed. ([Apple, Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/))

**Stage Manager: not announced.** Apple's announcement and OS deep-dive make no mention of Stage Manager, floating windows, external-display windowing, or three- and four-app layouts ([MacRumors, 2026-09-10](https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/); [MacObserver comparison](https://www.macobserver.com/tips/round-ups/iphone-duo-split-view-vs-ipad-multitasking/)). Split View on iPhone Duo is deliberately *simpler* than iPad multitasking, not a superset of it. **Unverified as an absence** — Apple has not said "no Stage Manager," it has simply never mentioned it.

### 1.6 What iOS 27 itself does differently

From [MacRumors, 2026-09-10](https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/):

- The interface reshapes as the device folds, unfolds and switches displays, keyed to hinge angle rather than just open/closed.
- Lock Screen controls, the Dock and app navigation now sit **along the side** of the display rather than across the bottom.
- The Dynamic Island runs **vertically** along the side of the outer display; the status bar became "a circular, flexible system that fits into the corner."
- Content shifts away from the crease when partially folded, where taps register poorly.
- The keyboard splits when the display is partly folded.
- Fully open, the Home Screen shows two pages.

### 1.7 The new and changed APIs developers must adopt

All from Apple's six Tech Talks, published 2026-09-09 and indexed at [developer.apple.com/iphone-duo](https://developer.apple.com/iphone-duo/):

| Talk | URL | Length |
|---|---|---|
| Design for iPhone Duo | [111466](https://developer.apple.com/videos/play/tech-talks/111466/) | 10:45 |
| Prepare your app for iPhone Duo | [111461](https://developer.apple.com/videos/play/tech-talks/111461/) | 10:10 |
| Raise the bar with iPhone Duo | [111462](https://developer.apple.com/videos/play/tech-talks/111462/) | 15:43 |
| Strike a pose with adaptive layouts on iPhone Duo | [111463](https://developer.apple.com/videos/play/tech-talks/111463/) | 18:01 |
| Leverage multiple displays and scenes on iPhone Duo | [111464](https://developer.apple.com/videos/play/tech-talks/111464/) | 7:17 |
| Build a great camera experience for iPhone Duo | [111465](https://developer.apple.com/videos/play/tech-talks/111465/) | 9:27 |

(Talk list and durations from [Sarunw, 2026-09-10](https://sarunw.com/posts/iphone-duo-tech-talks/), cross-checked against the Apple pages themselves.)

**Reserved regions** — [Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/). Hardware features that shape the usable layout area, in two kinds:
- **Division regions** — the hinge. Divides a display area into smaller usable regions. Active only when partially folded; **zero width when flat**.
- **Occlusion regions** — the FaceTime camera and similar. Occludes rather than divides.
- Queried with `proxy.reservedRegions(kind: .division)` in SwiftUI (inside a `GeometryReader`) or `view.reservedRegions(kind:)` in UIKit; `.includeInactive` returns regions that are not currently active, for higher-level decisions such as preferring an even number of grid columns.

**`ReservedRegion` / `UIViewReservedRegion`** — **new in iOS 27.1**. Lets custom UI claim as much screen space as possible without colliding with system UI ([Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/)).

**`ArrangementView` / `UIArrangementViewController`** — [Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/). A container that arranges a primary and a secondary view according to an "arrangement," computed from size classes, aspect ratio and active division regions. Two styles: `.split` (divides the bounds; horizontal when wider than tall, vertical when taller, single view when it cannot split) and `.overlay` (stacks above/below, moves to side-by-side when the device folds; the overlaid view reads `overlayArrangementZIndex` to decide whether to collapse). Anti-patterns Apple names explicitly: do **not** put a `NavigationSplitView` inside an `ArrangementView` (no navigation infrastructure), and avoid `ArrangementView` inside `List` or `ScrollView`.

**Hinge APIs** — [Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/). SwiftUI `.onHingeChange { previous, context in ... }`; UIKit `UIHingeInteraction`. Reports coarse status (`closed`, `partiallyOpen`, `fullyOpen`) and a continuous angle. A **null hinge means the device has none**, which is how the API stays backward compatible. For interaction effects only, not layout.

**Vertical bars** — [Tech Talk 111462](https://developer.apple.com/videos/play/tech-talks/111462/). On the inner display, navigation bars, toolbars and tab bars rotate 90° into a vertical stack at the side, preserving vertical space and improving reach; they return to horizontal in portrait. This is **opt-in and requires rebuilding against the latest SDK** *and* using bars provided by the navigation containers (`NavigationStack`, `NavigationSplitView`, `UINavigationController`, `UITabBarController`). Content from custom `UINavigationBar`, `UITabBar` or `UIToolbar` instances is **ignored** for vertical placement. New knobs: `.axisBehavior(.verticalPreferred / .horizontalOnly)`, `.toolbarVerticalCompressionBehavior(.prefersToolbarItems)`, `.visibilityPriority(.high)`, and an opt-out `.toolbarVerticalBehavior(.disabled)` / `preferredVerticalBarBehavior`. Symbol-only items are preferred because vertical bars have fixed width and flexible item height.

**Adaptive containers get it free** — [Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/). `NavigationStack`, `NavigationSplitView`, `TabView`, `List`, `ScrollView`, `UISplitViewController` and `UITabBarController` are fully adaptive across every pose: columns collapse when closed and tile or overlay when open. The system also repositions action sheets, alerts, menus and popovers to stay clear of the hinge, keeps split-view columns evenly split, and increases grid spacing around the hinge while preserving outer margins. `TabView { }.defaultTabBarPlacement(.sidebar)` turns a tab bar into a sidebar on the inner display.

**Asymmetric safe areas** — [Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/), stated as a correctness bug pattern:

```swift
// WRONG - assumes symmetric insets
let width = view.bounds.width - view.safeAreaInsets.left * 2
// CORRECT - each side independent
let width = view.bounds.inset(by: view.safeAreaInsets).width
```

**Concentricity** — `ConcentricRectangle()` in SwiftUI, `UICornerConfiguration` in UIKit (iOS 26+), to match the screen corners ([Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/)).

### 1.8 What Apple says about apps that are not updated

Apple's line in [Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/) is that "apps run on iPhone Duo even without recompiling," and that screen usage improves with each SDK version. The three tiers, reported consistently by three independent sources:

| Build target | Behaviour |
|---|---|
| **Pre-iOS 27 SDK** (no rebuild) | Runs letterboxed — "fits the single app view in a safe area around a black background," keeping the original aspect ratio. Unused space on both sides. |
| **iOS 27 SDK** | "Takes advantage of much more of the iPhone Duo display," extending to the left of the status bar area and avoiding the camera, but "there's still blank space not being used." |
| **iOS 27.1 SDK** | Full edge-to-edge, with vertically arranged navigation and toolbar items. "Apple's apps and third-party apps that want to offer the best experience for iPhone Duo will use this style." |

Sources: [9to5Mac, 2026-09-09](https://9to5mac.com/2026/09/09/heres-how-iphone-duo-treats-apps-not-optimized-for-the-foldable-display/) (quotations above); [blakecrosley.com, 2026-09-09](https://blakecrosley.com/blog/iphone-duo-for-developers); [dev.to, arshtechpro, 2026-09-09](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5).

**All apps automatically participate in Split View** regardless of tier — an app that already resizes correctly on iPad or under iPhone Mirroring is already compatible ([Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/)).

**No deadline, no App Store requirement.** 9to5Mac states the compatibility mode exists precisely so Apple can "support existing apps without requiring developers to update them before the iPhone Duo launches," and that "there's no deadline that shuts off existing apps" ([9to5Mac, 2026-09-09](https://9to5mac.com/2026/09/09/heres-how-iphone-duo-treats-apps-not-optimized-for-the-foldable-display/)). No App Store Review Guidelines change was found in any source. **Unverified as an absence:** not finding a deadline is not proof none exists, but no official or press source reports one as of 2026-09-12.

### 1.9 Tooling state as of today

From [developer.apple.com/iphone-duo](https://developer.apple.com/iphone-duo/), fetched 2026-09-12:

| Resource | State |
|---|---|
| Six Tech Talk videos | **Available now** |
| HIG "Designing for iPhone Duo" | **Available now** |
| Guide "Preparing your app for iPhone Duo" | **Coming later this month** |
| **Xcode 27.1 beta** (the SDK, and the iPhone Duo simulator in Device Hub) | **Coming later this month** |
| iPhone Duo workshops at Apple Developer Centers | Coming later this month |
| Group Labs (online) | 2026-09-16, 8–9 p.m. PT; 2026-09-17, 8–9 a.m. PT |
| Photos & Camera Q&A | 2026-09-23, 7–9 a.m. and 6–8 p.m. PT |
| SwiftUI Q&A | 2026-09-23, 8–10 a.m. and 5–7 p.m. PT |
| UIKit Q&A | 2026-09-23, 8–10 a.m. and 5–7 p.m. PT |

Corroboration on the dates and the SDK gap: [9to5Mac, 2026-09-09](https://9to5mac.com/2026/09/09/apple-launches-iphone-duo-developer-resources-ahead-of-october-release/). The iPhone Duo simulator was reported absent from Device Hub in Xcode 27 RC ([@SwiftDev_UI on X](https://x.com/SwiftDev_UI/status/2097766208732876934), **unverified**, single social-media post). Some blog posts describe the simulator's fold/rotate on-screen controls in the present tense; on 2026-09-12 Apple's own page still says "coming later this month," so those descriptions are read off the Tech Talk footage, not from a downloaded Xcode.

**Practical consequence:** roughly six weeks separate the announcement (2026-09-09) from the ship date (2026-10-23), and the SDK occupies only part of that window. Nobody — Apple included — can have tested a Flutter app on this device yet.

---

## Part 2 — What Flutter has today

Baseline: **Flutter 3.47.0, released 2026-08-12** (hotfix 3.47.1 about a week later, with Dart 3.13). [Release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0); [What's new in Flutter 3.47, 2026-08-12](https://flutter.dev/blog/whats-new-in-flutter-3-47).

### 2.1 The headline: nothing shipped for iOS foldables

Neither the Flutter 3.47 release notes nor the 3.47 blog post mentions foldables, display features, hinges, iPhone Duo, or iOS 27.1 anywhere. Verified by direct fetch of both pages on 2026-09-12.

### 2.2 `MediaQuery.displayFeatures` — Android only, by documentation

The official API reference for `FlutterView.displayFeatures` says, verbatim: **"This list is populated only on Android. If the device has no display features, this list is empty."** ([api.flutter.dev](https://api.flutter.dev/flutter/dart-ui/FlutterView/displayFeatures.html), live reference, undated).

`DisplayFeatureType` has three values — `hinge` (a physical separator, as on the Surface Duo), `fold` (a zero-width crease in a flexible display) and `cutout` (camera notches). A posture `state` is populated for folds and hinges only, and is unknown for cutouts. ([Microsoft Learn, "MediaQuery Display Features"](https://learn.microsoft.com/en-us/dual-screen/flutter/mediaquery))

On iOS, `displayFeatures` is an **empty list**, fold or no fold. Nothing in the engine maps Apple's reserved regions into it.

Even on Android the mechanism has open correctness bugs, e.g. [flutter/flutter#155658](https://github.com/flutter/flutter/issues/155658) "DisplayFeature.bounds not being updated if the device is rotated."

### 2.3 The one iPhone Duo issue in flutter/flutter

**[flutter/flutter#192515](https://github.com/flutter/flutter/issues/192515)** — "Proposal: populate `MediaQuery.displayFeatures` on iOS for iPhone Duo (foldable)." Filed by community member **mirzaaghazadeh on 2026-09-09**, the announcement day. Labels: `P2`, `c: proposal`, `engine`, `fyi-framework`, `platform-ios`, `team-ios`. **State: open, with no maintainer response** as of a direct fetch on 2026-09-12.

It proposes mapping iOS 27.1's reserved regions onto the existing abstraction — division regions → `DisplayFeatureType.fold`, occlusion regions → `DisplayFeatureType.cutout` — so apps do not each have to write a platform channel. It also identifies a genuine model gap: iOS can express "this device has a fold, currently flat," and Flutter's list-based model cannot, because an inactive feature is simply absent from the list. A naive mapping therefore could not distinguish a flat iPhone Duo from a non-foldable iPhone.

No other flutter/flutter issue about iOS Split View, hinge APIs or iOS multitasking was found in connection with the announcement.

### 2.4 Multi-window — desktop only, `@internal`, main-channel flag

- **Not usable from stable.** As of an article dated **2026-08-04**, "the framework ships a complete windowing API… but every class in it is marked `@internal`… and every constructor throws `UnsupportedError` unless the windowing feature flag is on. That flag is only available on the `main` channel." The flag is `flutter config --enable-windowing`. ([startdebugging.net, 2026-08-04](https://startdebugging.net/2026/08/how-to-enable-multi-window-support-in-a-flutter-desktop-app/))
- **Desktop only.** The umbrella issue is [flutter/flutter#142845](https://github.com/flutter/flutter/issues/142845) "☂️ Multi View for Windows/MacOS", opened 2024-02-02, still open. The experimental-API rollout issue is [#171720](https://github.com/flutter/flutter/issues/171720) (opened 2025-07-07); the pre-launch checklist is [#177586](https://github.com/flutter/flutter/issues/177586) (opened 2025-10-27), which still describes multi-window as hidden behind a feature flag with unfinished items.
- **3.47 added to it but did not release it.** The 3.47 notes list popup windows for Win32, `windowHandle` access to native handles, a sized-to-content window API, and API renames — described in the blog as "experimental desktop windowing APIs." Nothing for mobile.
- **Android** multi-window/multi-display has two open, unimplemented requests: [#134405](https://github.com/flutter/flutter/issues/134405) (2023-09) and [#138167](https://github.com/flutter/flutter/issues/138167) (2023-11).
- **iOS** has no analogous multi-window *windowing* proposal at all. What exists for iOS is the `UIScene` **lifecycle migration**, which is about launching legally under Xcode 27 — not about presenting multiple windows.

### 2.5 `UIScene` and iOS 27 — the one thing Flutter did do in time

From the [3.47 blog, 2026-08-12](https://flutter.dev/blog/whats-new-in-flutter-3-47), verified by direct fetch:

> "The iOS 27 SDK now mandates the `UIScene` lifecycle for all UIKit-based apps."

Apps built with Xcode 27 that do not adopt `UIScene` **fail to launch on startup**. Flutter's CLI auto-migrates most apps; manual migration is needed for custom `AppDelegate` code or plugins still on the legacy lifecycle. The same release raised the minimum iOS deployment target from **13 to 15** and macOS from 10.15 to 12, both "to support Xcode 27."

Related landed work in 3.47: [PR #187987](https://github.com/flutter/flutter/pull/187987) "[ios] Filter UIScene events to those relating to Flutter VC scene"; [PR #188520](https://github.com/flutter/flutter/pull/188520) (macOS minimum); [PR #188189](https://github.com/flutter/flutter/pull/188189) (drop iOS 14/15 availability checks); [PR #185424](https://github.com/flutter/flutter/pull/185424) "[pv] Skip non-tappable web view workaround on ios 26.4".

The Xcode 27 launch failure was tracked and fixed: [#187781](https://github.com/flutter/flutter/issues/187781) (opened 2026-06-10 against 3.44.1 — apps failed because Flutter's default 13.0 target fell below Xcode 27's 15.0 minimum), closed as duplicate of [#187741](https://github.com/flutter/flutter/issues/187741). Also open/unclear: [#187743](https://github.com/flutter/flutter/issues/187743) "`flutter doctor` can't find iOS 27 simulator runtime" (**unverified** resolution status).

**Flutter's iOS multi-scene support is young and has rough edges**, all predating the Duo:
- [#172147](https://github.com/flutter/flutter/issues/172147) — "Flutter and iOS multiscene: Last session frame visible before splash screen."
- [#185686](https://github.com/flutter/flutter/issues/185686) / [#170167](https://github.com/flutter/flutter/issues/170167) — confusion in Flutter's own migration guidance about how a `FlutterEngine` is associated with a scene in `scene:willConnectToSession:options:`; it is not automatic, and must be registered with `FlutterSceneDelegate` / `FlutterPluginSceneLifeCycleDelegate` or it auto-registers only once the `FlutterViewController`'s view is in the hierarchy.
- [#183586](https://github.com/flutter/flutter/issues/183586) — deep-link regressions after the UIScene migration in 3.38.10 (which dates the migration to roughly 3.38).
- [#147983](https://github.com/flutter/flutter/issues/147983) — "[ios][camera] Enable camera while in multitasking mode (split view in iPadOS)": precedent that Flutter has had feature gaps in *existing* iPad Split View scenarios long before this device.

**iOS 27.1 and iPhone Duo hardware with Flutter: entirely unverified.** Both ship 2026-10-23, after the current Flutter stable (3.47, 2026-08-12). No one has published results.

### 2.6 `dual_screen` / `TwoPane` — dead for this purpose

[pub.dev/packages/dual_screen](https://pub.dev/packages/dual_screen), fetched 2026-09-12: version **1.0.4**, last published **"3 years ago"** (≈2023). The package's own description: **"This plugin will work on any platform, but only Android actually has foldable and dual screen devices."** It documents testing against the Surface Duo emulator and Android Studio foldable emulators. No iOS support, no updates.

Corroborated independently by [dev.to, mirzaaghazadeh, 2026-09](https://dev.to/navid_mirzaaghazadeh_e775/what-actually-changes-in-your-ios-app-for-iphone-duo-11fo) ("hasn't been published in about three years") and by [iphoneduosupport.com/frameworks/flutter](https://iphoneduosupport.com/frameworks/flutter/) (community tracker, undated, live 2026-09-12).

`TwoPane` remains usable as a plain two-pane *widget* driven by your own breakpoints. It just cannot tell you anything about a fold on iOS.

### 2.7 Community read on Flutter's readiness

- [iphoneduosupport.com/frameworks/flutter](https://iphoneduosupport.com/frameworks/flutter/) (community-run tracker, not affiliated with Apple or Flutter): "Flutter has not shipped iPhone Duo support or published guidance for it." It notes `displayFeatures` is documented as Android-only and returns empty on iPhone Duo regardless of fold state, and recommends a platform channel to Swift to read reserved regions directly.
- [dev.to, mirzaaghazadeh, 2026-09](https://dev.to/navid_mirzaaghazadeh_e775/what-actually-changes-in-your-ios-app-for-iphone-duo-11fo): "Neither Flutter nor React Native supports iPhone Duo yet." The same author filed #192515. This post is explicitly speculative about API signatures — it states "I could not verify these API signatures against the SDK. Xcode 27.1 hadn't shipped when I wrote this."
- A third-party post [verygood.ventures, "Flutter and WWDC 2026: What iOS 27 Means for Your App"](https://verygood.ventures/blog/wwdc-2026-through-a-flutter-lens/) exists but its contents were **not fetched or verified**; listed only as a search hit.

### 2.8 Flutter capability matrix

| Capability | In Flutter 3.47 stable? | Platforms | Evidence |
|---|---|---|---|
| Launch correctly under the iOS 27 SDK (`UIScene`) | **Yes** — auto-migration in 3.47 | iOS ≥ 15 | [3.47 blog, 2026-08-12](https://flutter.dev/blog/whats-new-in-flutter-3-47) |
| Participate in Split View at all | **Yes, for free** — the OS resizes the window; Flutter apps resize | iOS | [Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/) (all apps participate); Flutter side **unverified on device** |
| `MediaQuery` / `LayoutBuilder` react to resize | Yes, normal mechanism | all | Standard behaviour; **unverified under iOS 27.1 Split View specifically** |
| Per-edge (asymmetric) safe-area insets representable | Yes — `MediaQueryData.padding` is an `EdgeInsets` with independent sides | all | API design; correctness under Duo geometry **unverified** |
| Know a fold exists / where it is | **No** | — | `displayFeatures` Android-only ([api.flutter.dev](https://api.flutter.dev/flutter/dart-ui/FlutterView/displayFeatures.html)); proposal [#192515](https://github.com/flutter/flutter/issues/192515) open, unanswered |
| Hinge angle / posture | **No** | — | No API; platform channel to `UIHingeInteraction` required |
| Reserved regions (hinge, camera occlusion) | **No** | — | No API; platform channel required |
| iOS vertical navigation/tool bars | **No** | — | Apple's own bars only; Flutter draws its own ([Tech Talk 111462](https://developer.apple.com/videos/play/tech-talks/111462/): custom bars are ignored for vertical placement) |
| Multiple windows of one app | **No** on mobile; experimental+flagged on desktop | Win/Linux/macOS, main channel only | [#142845](https://github.com/flutter/flutter/issues/142845), [#177586](https://github.com/flutter/flutter/issues/177586), [startdebugging.net 2026-08-04](https://startdebugging.net/2026/08/how-to-enable-multi-window-support-in-a-flutter-desktop-app/) |
| Scene accessories (outer-display UI) | **No** | — | Would need native scene work beyond Flutter's model |
| `dual_screen` / `TwoPane` for fold awareness | **No** (widget works; fold detection Android-only, ~3 years stale) | Android | [pub.dev](https://pub.dev/packages/dual_screen) |

---

## Part 3 — What it means for Boardhop, concretely

All figures below use the point sizes from §1.2 (inner **669 × 951 pt**, outer **466 × 678 pt**, Split View pane ≈ **475 × 669 pt**), which are **partly unverified** — redo this table against the Xcode 27.1 simulator when it ships.

### 3.1 Breakpoints: they land well, with one near miss

`Breakpoint.fromWidth` in `lib/theme/layout.dart` is `< 600 → compact`, `< 840 → medium`, else `expanded`.

| Situation | `MediaQuery` width | Boardhop `Breakpoint` | Verdict |
|---|---|---|---|
| Folded, portrait (outer) | 466 | `compact` | Correct — phone layout |
| Folded, landscape (outer) | 678 | `medium` | Reasonable |
| Unfolded, tall pose | 669 | `medium` | Reasonable |
| Unfolded, wide pose | 951 | `expanded` | Correct — tablet layout, and this is the pose the device is designed for |
| Split View pane | ≈ 475 | `compact` | Correct — phone layout in half the inner display |

That is a good result and it is not luck: the app was built for the `expanded` breakpoint on the Pixel Tablet at 800 × 500 dp, and the inner display at 951 × 669 pt is the same class of surface. **The inner display will get Boardhop's tablet layout, and a Split View pane will get its phone layout, with no code change.**

**The near miss.** `ContentColumn.twoColumnMin` is 960, and `SideBySide` compares against the width it is *given*, which is `ContentColumn`'s cap, not the window. On the inner display in the wide pose:

```
ContentColumn.widthFor(951) = min(951, max(840, min(1120, 951 - 2*24)))
                            = min(951, max(840, 903)) = 903
```

903 < 960, so **`SideBySide` stacks instead of going two-column on the inner display** — it misses by 57 pt. Forms and detail pages that were designed to put two groups of sections side by side on a tablet will fall back to a single stacked column on the very device whose 1.42 aspect ratio is ideal for two panes. Lowering `twoColumnMin` to about 880, or comparing against the window width rather than the content width, would fix it. Worth a decision from Kelly rather than a silent change; noting it here and in NEXT-STEPS is the right next step.

### 3.2 `SafeArea` — in good shape

Apple's specific warning is code that assumes symmetric insets (§1.7). A grep of `lib/` on 2026-09-12 found **no** `padding.left`/`padding.right`/`padding.horizontal` arithmetic and no `viewPadding` use anywhere. `SafeArea` is used in 20+ files and handles each edge independently by construction, and `MediaQueryData.padding` is an `EdgeInsets` that can represent asymmetry. The CLAUDE.md convention — every page body outside the project shell wraps in `SafeArea(top: false, bottom: false)`, and `Scaffold` insets nothing on the sides — is exactly the shape Apple is asking for.

Residual risk is Flutter's, not Boardhop's: Flutter's inset handling has a history of bugs on unusual geometry — [#60346](https://github.com/flutter/flutter/issues/60346) (asymmetric handling on OnePlus 7 Pro), [#97609](https://github.com/flutter/flutter/issues/97609) (`maintainBottomViewPadding` during keyboard animation on iOS), [#174790](https://github.com/flutter/flutter/issues/174790) (Android insets with keyboard on targetSdk 35). None is Duo-specific; none can be, yet. **Unverified for this device.**

### 3.3 `display_cutout.dart` — the one thing that is now wrong

`lib/core/display_cutout.dart` asks the iOS `AppDelegate` for `interfaceOrientation` over the `com.kammcs.boardhop/display` channel, because Flutter's insets are symmetric in landscape and cannot say which side holds the Dynamic Island.

Apple's guidance directly undercuts that approach on this device: **"the inner display doesn't honor supported interface orientations, so use size classes rather than orientation"** ([Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/)). And on the outer display the Dynamic Island "runs vertically along the side" ([MacRumors, 2026-09-10](https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/)), which is not the geometry the `landscapeLeft → right` mapping encodes. On iPhone Duo the channel will likely return an orientation that does not describe where the cutout is. `CutoutSide.unknown` is already a handled case, so this should degrade rather than crash — **unverified**, and the right long-term answer is to replace the channel with a `reservedRegions(kind: .occlusion)` query on iOS 27.1 and keep the current path for older iOS. That would also answer the fold, since `reservedRegions(kind: .division)` is the same call with a different kind.

Worth noting: `glass_shell_layout.dart:87` branches on `mq.orientation`. In Flutter that is derived from the *size* (width vs height), not from UIKit's interface orientation, so it keeps working — the rail floats at the side in the wide pose and the bar sits at the bottom in the tall pose and in a Split View pane. Apple's "don't use orientation" warning is about `UIInterfaceOrientation`, which Flutter apps do not normally read. Boardhop reads it in exactly one place: `display_cutout.dart`.

### 3.4 `NavigationRail` and the glass shell

`project_shell.dart` uses `NavigationRail`, and `glass_shell_layout.dart` draws a custom `GlassNavigationRail`. Both are Flutter-drawn widgets, so they will render at whatever size the window reports and will not participate in iOS 27.1's vertical-bar system — Apple is explicit that only bars provided by `UINavigationController` / `UITabBarController` / `NavigationStack` / `NavigationSplitView` are considered, and "content from custom `UINavigationBar`, `UITabBar` or `UIToolbar` instances is not considered for vertical placement" ([Tech Talk 111462](https://developer.apple.com/videos/play/tech-talks/111462/)). A Flutter app is, from iOS's point of view, entirely custom bars.

This is not a regression — it is the standing cost of Flutter's draw-everything model, the same reason Boardhop draws its own glass rail "in the spirit of iOS 26's glass sidebars" instead of getting one. The happy accident is that Boardhop's rail already sits at the *side* in the wide pose, which is precisely the arrangement Apple moves system bars to on the inner display. Boardhop will look like it adopted the platform convention without having adopted the API. No specific Flutter issue was found about `NavigationRail` or dialogs under live resize (**unverified either way**).

### 3.5 The WebView is the fragile piece

Boardhop runs `html_editor_enhanced` 2.7.1 on `flutter_inappwebview` 6.2.0-beta.3 (pubspec overrides) for rich-text work item fields — a platform view. Resizing a live platform view is a documented weak spot across platforms today, entirely independent of the Duo:

- [#34647](https://github.com/flutter/flutter/issues/34647) — resizing a PlatformView/WebView container exhausts resources and soft-boots Android.
- [#162003](https://github.com/flutter/flutter/issues/162003) — `[webview_flutter_android]` WebView fails to resize in `SystemUiMode.edgeToEdge` after a display-size change.
- [#155749](https://github.com/flutter/flutter/issues/155749) — WebView temporarily stretches content on resize.
- [#146576](https://github.com/flutter/flutter/issues/146576) — WebView window size is zero when not visible (iOS-relevant).
- [#136192](https://github.com/flutter/flutter/issues/136192) — "[ios] Stuck up in a scenario with multiple flutter screens containing PlatformView."
- [#127095](https://github.com/flutter/flutter/issues/127095) — iOS crash combining `PlatformView` and `BackdropFilter`. Relevant because the glass shell uses backdrop blur.

iOS 27.1 Split View resizes the app's window **live**, not by rotate-and-relaunch, and folding does it again. `rich_text_control.dart` already carries a hard-won comment that the WebView occupies a "stable slot… never insert a widget above it" because doing so disposes and recreates it (spike F3). A width change from 951 to 475 mid-edit is exactly the event that re-lays out that slot. **Expect the rich-text editor to be the first thing to break, and test it explicitly**: open a work item form on the inner display, invoke Split View, fold and unfold, and check the editor keeps its content and its height. This is inference from adjacent verified bugs, not a Duo-specific report — there are none yet. **Unverified.**

### 3.6 Multiple windows of Boardhop

`ios/Runner/Info.plist` already declares `UIApplicationSceneManifest` with a `UIWindowSceneSessionRoleApplication` configuration named `flutter`, and `UIApplicationSupportsMultipleScenes` set to **`false`**. That is the standard Flutter template and it is what makes the app launch legally under the iOS 27 SDK.

Two consequences. First, **Boardhop is already `UIScene`-migrated** — the mandatory part of iOS 27 is done. Second, **two windows of Boardhop side by side will not be possible** while that flag is false, and flipping it to `true` is not a one-line change: Flutter's iOS multi-scene support is the young, rough-edged area catalogued in §2.5, and Flutter has no framework-level notion of a second window on mobile at all. Two *different* apps side by side, one of them Boardhop, works regardless — that is the OS resizing one window.

For a code-review app this is a real feature loss rather than a cosmetic one: the obvious Duo use case is a pull request diff in one pane and the work item in the other. Today that has to be two panes *inside* one Boardhop window — which the 1.42 aspect ratio and the existing `SideBySide` machinery are well suited to, once §3.1 is fixed.

### 3.7 The Kanban board and the diff viewer

The hand-rolled Kanban (`LongPressDraggable` + `DragTarget`) and the diff engine (own Myers diff + `re_highlight` + `super_sliver_list`) are pure Flutter widgets with no platform-view or orientation dependency, so they follow the breakpoints and should need nothing. Two things to check on hardware: long-press drag across the hinge crease — Apple notes taps register poorly at a partial fold ([MacRumors, 2026-09-10](https://www.macrumors.com/2026/09/10/apple-details-how-ios-27-adapts-to-iphone-duo/)) — and whether `super_sliver_list`'s cached extents survive a live width change from 951 to 475. Both **unverified**.

### 3.8 Which compatibility tier Boardhop lands in

Per CLAUDE.md, Boardhop currently builds with Xcode 26.6. Against the ladder in §1.8 that puts it in **tier 1: letterboxed on a black background** on iPhone Duo. Reaching tier 3 (edge to edge, no wasted space) requires building against the **iOS 27.1 SDK**, which needs Xcode 27.1 — not yet downloadable (§1.9). Since `tool/ship-ios.sh` builds the TestFlight IPA on the Mac, the practical sequence is: wait for Xcode 27.1 beta later this month, install it, rebuild, and run the app in the iPhone Duo simulator's fold/rotate controls in Device Hub before the device ships on 2026-10-23. There is no deadline, so nothing forces this — but a letterboxed app on a $1,999 flagship is a poor first impression for a paid-tier product, and the gap between "launches fine" and "looks native" is one SDK bump plus the `twoColumnMin` fix.

### 3.9 Recommended posture, in order

1. **Do nothing structural yet.** The SDK does not exist, the device does not exist, and Flutter has published no guidance. Any hinge or reserved-region work written today is written against API spellings nobody has compiled.
2. **When Xcode 27.1 beta lands** (Apple says later this month): install it on the Mac, rebuild, and drive the iPhone Duo simulator through all four layout situations plus Split View, with `tool/shot-ios.sh` extended for the new device. Verify the §3.1 breakpoint table against real numbers and correct this document.
3. **Fix `SideBySide`** so the inner display gets two columns (§3.1). This is a pure Flutter change, testable on the existing Pixel Tablet and iPad simulators today at 903 dp of content width, and it is worth doing whether or not the Duo matters.
4. **Test the rich-text WebView under live resize** (§3.5) as the highest-risk item.
5. **Plan to replace `display_cutout.dart`'s orientation channel** with a `reservedRegions(kind: .occlusion)` query on iOS 27.1, keeping the current path for older iOS (§3.3). Adding `kind: .division` to the same channel gives Boardhop fold awareness without waiting for [#192515](https://github.com/flutter/flutter/issues/192515) — which, at `P2` with no maintainer response, should not be counted on.
6. **Do not expect multi-window Boardhop.** Treat it as out of scope and put the two-pane experience inside one window instead (§3.6).
7. **Watch [#192515](https://github.com/flutter/flutter/issues/192515)** and the Flutter 3.48 release notes (next quarterly, so roughly November 2026 — **unverified**) for any iOS foldable work.

---

## Part 4 — Calibration: the other frameworks

The short version: **Boardhop is not disadvantaged by being a Flutter app here.** No cross-platform framework has shipped anything, and only Flutter has even a filed issue.

| Framework | Official statement on iPhone Duo? | Fold / hinge API today | Multi-scene or Split View on iOS |
|---|---|---|---|
| **Flutter** | None | `displayFeatures` Android-only; empty on iOS | `UIScene` lifecycle migrated (3.47); no multi-window on mobile |
| **React Native** | None found | None at all | Partial/legacy scaffolding only |
| **.NET MAUI** | None found | `TwoPaneView` exists but is Android/Jetpack-only | Not addressed |
| **Compose Multiplatform** | None found | Not addressed anywhere | Not addressed |
| **Native SwiftUI / UIKit** | Official: HIG page + six Tech Talks, 2026-09-09 | `onHingeChange` / `UIHingeInteraction`; `ReservedRegion`; `ArrangementView` | First-class; multi-scene on the inner display only |

### React Native

No statement found on [reactnative.dev/blog](https://reactnative.dev/blog) or in Expo's changelog ([expo.dev/changelog/sdk-54](https://expo.dev/changelog/sdk-54)), searched 2026-09-12. Community analysis is blunt: **"React Native has no fold API at all"** ([dev.to, mirzaaghazadeh, 2026-09](https://dev.to/navid_mirzaaghazadeh_e775/what-actually-changes-in-your-ios-app-for-iphone-duo-11fo)). Resize via `useWindowDimensions` and asymmetric insets via `useSafeAreaInsets` work in JS; fold and hinge need a native module.

React Native's `UIScene` story is *behind* Flutter's. [react-native#53602](https://github.com/react/react-native/issues/53602), opened 2025-09-04, shows Xcode 26 already warning that "UIScene lifecycle will soon be required" while RN internals (`RCTDeviceInfo`) still assumed an `AppDelegate.window`, crashing on rotate-while-backgrounded with a `SceneDelegate` (since fixed). Earlier partial work: [facebook/react-native#28147](https://github.com/facebook/react-native/pull/28147) "Make RCTKeyWindow multi-window aware…" (**unverified** date). Whether RN supports multiple scenes on iOS as a documented feature today is **unverified**; the evidence suggests partial/legacy support, not a supported feature.

### .NET MAUI

No Microsoft statement and no dotnet/maui issue mentioning iPhone Duo was found (searched 2026-09-12). **Microsoft.Maui.Controls.Foldable** — the Surface Duo-era package that provides `TwoPaneView` — is still published, **version 10.0.50, updated 2026-03-10** ([NuGet](https://www.nuget.org/packages/Microsoft.Maui.Controls.Foldable/10.0.50)). But per Microsoft Learn, its foldable-aware behaviour is **scoped to Android devices supporting Jetpack Window Manager**; on every other platform, explicitly including iOS, it degrades to "a configurable and responsive split view" with no fold-state awareness ([Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.maui.controls.foldable.twopaneview?view=net-maui-9.0), **wording paraphrased, unverified date**). Structurally identical to Flutter's `dual_screen`, but maintained.

### Kotlin Multiplatform / Compose Multiplatform

The least-covered of the four. JetBrains' Compose Multiplatform iOS reached Beta 2024-05 ([blog](https://blog.jetbrains.com/kotlin/2024/05/compose-multiplatform-1-6-10-ios-beta/)) and Stable 2025-05 ([blog](https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/)); none of those posts mentions foldables. **No YouTrack issue** about iPhone Duo, foldable iOS or iOS split-view adaptive layout was found (searched 2026-09-12). Compose's `WindowSizeClass` adaptive tooling derives from Jetpack Window Manager; whether it maps meaningfully to iPhone Duo window sizing is **unverified**. This is silence, not a stated position.

### Native SwiftUI / UIKit

Covered in Part 1. Apple has shipped a real API surface (reserved regions, arrangements, vertical bars, hinge, scene accessories) with a documented three-tier compatibility fallback and no enforced deadline — so the native path is "adopt when convenient, and you get most of it free from the standard containers," while every cross-platform path is "wait, or write a platform channel."

### Comparison coverage

- [iphoneduosupport.com](https://iphoneduosupport.com/frameworks/flutter/) — community tracker with per-framework pages for SwiftUI, UIKit, React Native, Flutter, Unity and web views. Undated, live 2026-09-12. Recommends the same native-bridge fallback for Flutter and React Native alike.
- [dev.to, mirzaaghazadeh, 2026-09](https://dev.to/navid_mirzaaghazadeh_e775/what-actually-changes-in-your-ios-app-for-iphone-duo-11fo) — direct Flutter/RN side-by-side.
- **No comparison article found that includes .NET MAUI or Compose Multiplatform.** The September 2026 commentary cycle is concentrated on Flutter vs React Native vs native; MAUI and KMP are absent from it entirely.

---

## Appendix — Open questions to settle once Xcode 27.1 ships

| # | Question | Why it matters |
|---|---|---|
| 1 | Actual `MediaQuery.size` in points for both displays and for a Split View pane | The whole of §3.1 rests on inferred point sizes |
| 2 | Is the Split View divider really fixed 50/50? | Sources conflict (§1.5); a draggable divider means arbitrary widths, not one extra breakpoint |
| 3 | Does iOS report a Split View pane as compact or regular horizontal? | Determines whether Apple's containers and Boardhop's breakpoints agree |
| 4 | What `MediaQuery.padding` reports on the inner display, per edge, at each pose | Confirms `SafeArea` handles the real asymmetry |
| 5 | Does `MediaQuery` update smoothly during a fold, or only at pose boundaries? | Determines whether layout animates or snaps |
| 6 | Does the `html_editor_enhanced` WebView survive a 951 → 475 pt live resize? | Highest-risk component (§3.5) |
| 7 | What does the `com.kammcs.boardhop/display` channel actually return on the inner display? | §3.3; may be silently wrong rather than `unknown` |
| 8 | Does a Flutter app built with the iOS 27.1 SDK reach tier 3 automatically, or does it need `ReservedRegion` adoption Flutter cannot make? | Decides whether a rebuild is sufficient (§3.8) |
| 9 | Does long-press drag work across the crease at a partial fold? | Kanban board (§3.7) |
| 10 | Has Flutter responded to [#192515](https://github.com/flutter/flutter/issues/192515)? | Decides whether to write the platform channel or wait |
