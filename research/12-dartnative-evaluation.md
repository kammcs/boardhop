# 12. DartNative versus Flutter for Boardhop, and the iPhone Duo

**Date:** 2026-09-12
**Ask (Kelly):** is DartNative (dartnative.com) mature enough to consider, given that Flutter may struggle with the iPhone Duo's new features while a native-views framework would handle them "seamlessly"? Research it, look at the codebase, estimate the migration pain.
**Method:** two parallel research agents (findings in `12a-dartnative-findings.md` and `12b-iphone-duo-and-flutter.md`, every claim dated and sourced) plus a dispatcher inventory of the codebase. This document is the reconciled verdict.

## Verdict

**Do not migrate. Do not prototype. Revisit no earlier than mid-2027, and only if the checkpoints in section 5 are met.** The Duo argument is real in principle but does not survive contact with the facts: DartNative has said nothing about the device, ships against iOS 26 while the Duo runs iOS 27.1, and the migration would be a rewrite of most of the app with no test framework on the other side. The cheap, correct move is to make the existing Flutter layouts Duo-ready (section 4), which is days of work.

## 1. What DartNative is (verified 2026-09-12)

- A **new** commercial framework from Presence Network Inc., unrelated to the older ByteDance-lineage `dart_native` FFI bridge on pub.dev. It re-implements the Flutter widget API on top of real UIKit and Android Views, with its own engine, its own `dn` CLI, Yoga layout, and its own package registry (dartpub.dev). It does not use the Flutter SDK; "the only change is the import" is the marketing line, "most of your widget code works as-is" is the README's.
- **First public preview 2026-07-31; one follow-up preview 2026-09-08** (seven iOS 26 fixes). No version numbers. Closed source with a sunset clause (BSD-3 release if discontinued or twelve months idle, within a further ninety days). $49 or $99 per year above one production app.
- **Adoption:** 98 GitHub stars, 15 release-only commits, 0 PRs, 4 open and 0 closed issues (one P1: `dn publish` crashes on Windows, our primary host), 54–56 weekly installs per plugin, no third-party production app, no independent review, blog, talk or forum thread found. The two named production apps are the vendor's own, and no store build post-dating the framework's first preview could be confirmed.
- **Tooling gaps that matter here:** no widget or integration test framework at all, no DevTools, no debugger (a community request), no CI or Xcode/SwiftPM documentation, Windows install by manual extraction, no iOS Dynamic Type (fixed UIKit points), no documented `Semantics`, RTL filed as broken on 2026-09-12, no WebView in the widget catalog, no `LongPressDraggable`/`DragTarget`, no slivers (`FastList` instead), `PageView`/`TabBar`/`NestedScrollView`/`Dismissible` explicitly unsupported, `Offstage` unmounts state, all Dart on the UI thread with no documented isolate story.

## 2. What the migration would cost Boardhop

Codebase inventory (2026-09-12): 43,400 lines of Dart. `lib/features` 26,300 and `lib/theme` 770 are widget code; `lib/data` 13,500 and `lib/core` 1,240 are mostly pure Dart (22 of 28 data files import nothing from Flutter); the vendored `msal_auth` plugin is 1,100 lines of Dart over native MSAL. 99 of 133 library files import Flutter. 40 test files, 15 of them widget tests.

| Area | Fate under DartNative |
|---|---|
| Models, repositories, JSON cache, diff engine (`LineDiff`), highlighter runs | Port with small changes. Drift needs a custom `QueryExecutor` over `dartnative_sqlite` that nobody has written. `re_highlight` and `dio` should work as is. |
| Sign-in (`msal_auth`, vendored and patched, MethodChannel over native MSAL) | Rebuild from scratch against an undocumented FFI surface. Sign-in is the app's only door. |
| Routing (`go_router`, account-scoped routes, `StatefulShellRoute`) | Rewrite on DartNative's own Navigator. |
| State (`flutter_bloc`) | Port to plain `bloc`; named by the vendor as "the Flutter-bound one". |
| Rich text editor (`html_editor_enhanced` over `flutter_inappwebview`) | **No path.** No WebView in the catalog. This is a settled decision from spike F3 and the only editor that round-trips the customers' HTML. |
| Kanban (hand-rolled `LongPressDraggable` + `DragTarget`) | **No path.** Neither widget exists. |
| Diff viewer and file viewer (`super_sliver_list`, `re_editor`, `CustomPaint`) | Architecture change to `FastList`; `re_editor` rewritten. |
| Markdown and HTML rendering (`flutter_markdown_plus`, `flutter_widget_from_html_core`) | Rewrite; both are `RichText`-based. The HTML renderer is load-bearing for every work item description. |
| Pickers, share, notifications, launcher, prefs, paths (`image_picker`, `file_picker`, `share_plus`, `flutter_local_notifications`, `url_launcher`, `shared_preferences`, `path_provider`) | Vendor equivalents for four; no equivalent for pickers and share. |
| Theme (`BoardhopTheme`, `BoardhopColors`, tokens, glass rail with backdrop blur) | Re-express on native styling; the blur and the custom rail are the parts least likely to survive. |
| Tests | Unit tests survive under `dart test`; the 15 widget test files and the debug-build assert workflow that found the go_router and overflow bugs have no replacement. |

Tally over the 18 tracked dependencies: 1 confirmed unchanged, 1 probable, 5 vendor replacements, 11 with no equivalent. Roughly 27,000 lines rewritten, 15,000 ported, and three settled architectural decisions (rich text, Kanban, diff engine) reopened with no answer on the other side. That is a new app that happens to share models, not a migration.

## 3. The iPhone Duo, and where Flutter actually stands

- **Device:** announced 2026-09-09, ships 2026-10-23, from $1,999. Inner 7.6 inch (about 669 x 951 pt), outer 5.4 inch (about 466 x 678 pt), point sizes inferred from published pixels. **Runs iOS 27.1**, not iOS 26.
- **What changes for apps:** the inner display reports **regular x regular size classes in both orientations** and ignores supported orientations; the outer is compact wide. **Split View on iPhone** for the first time, fixed 50/50 with no draggable divider (one lower-quality source disagrees; settle in the simulator), each pane about 475 x 669 pt. New APIs in 27.1: reserved regions (`.division` for the hinge, `.occlusion` for the camera), arrangement views, a hinge interaction for effects only, vertical bars along the edge. Apple's guidance: branch on size classes, not idiom or orientation; never do symmetric safe-area arithmetic.
- **Unupdated apps keep running** on a three-tier ladder: pre-27 SDK letterboxed, 27 SDK more screen, 27.1 SDK edge to edge. No deadline, no store requirement. Xcode 27.1 with the SDK and the Duo simulator was still "coming later this month" on 2026-09-12.
- **Flutter 3.47 (2026-08-12):** did the mandatory part, migrating apps to the `UIScene` lifecycle the iOS 27 SDK requires and stating it is prepared for Xcode 27 and iOS 27. It has no fold awareness on iOS: `MediaQuery.displayFeatures` is Android-only, and the one issue (flutter/flutter#192515, filed on announcement day) is P2 with no maintainer reply. Multi-window stays desktop-only and experimental.
- **Peers:** React Native, .NET MAUI and Compose Multiplatform have no statement and no iOS fold API either; only Flutter has a filed issue. DartNative has not mentioned the device at all. Its architecture could inherit native chrome and split-view participation for free, but that is an inference, and a vendor that needed seven hand patches for iOS 26 navigation bars has not shown it survives a live fold resize.

## 4. What Boardhop should do for the Duo instead (small, concrete)

1. **Rebuild against the iOS 27.1 SDK** once Xcode 27.1 ships, to leave the letterboxed tier. Flutter 3.47 already handles the `UIScene` requirement.
2. **Breakpoints already land right:** the outer display and a Split View pane are compact, the inner display is expanded (the tablet layout). One miss: `ContentColumn.widthFor(951)` is 903 and `SideBySide.twoColumnMin` is 960, so the inner display stacks sections instead of using two columns on exactly the screen whose 1.42 ratio suits them. Lowering the threshold to about 880 fixes it. **Kelly's call.**
3. **`lib/core/display_cutout.dart` is wrong on this device:** it maps interface orientation to a cutout side, but the inner display ignores orientation and the outer display's island runs along the side. Degrade to `unknown` now; the right fix is a `reservedRegions` query over the same method channel, which also delivers the hinge (`.division`) for free and removes the wait on #192515.
4. **The WebView editor is the fragile piece** under a live Split View resize (platform-view resize bugs #34647, #162003, #155749, #146576, #136192, #127095, the last one relevant because the glass shell uses backdrop blur). The rich text control already keeps the editor in a stable slot; test it in the Duo simulator first.
5. `SafeArea` use is already asymmetric everywhere (no left-equals-right arithmetic in `lib/`), which is the bug Apple warns about most. `UIApplicationSupportsMultipleScenes` stays false: two Boardhop windows side by side is out of scope.
6. Follow flutter/flutter#192515 and the 12b appendix's ten simulator questions (divider draggable or not, exact point sizes, how `MediaQuery` reports the fold).

## 5. Revisit checkpoints for DartNative (all of them)

A versioned stable release with twelve months of changelog; a widget or integration test framework and IDE debugging; a named third-party production app on both stores; iOS Dynamic Type, a documented `Semantics` API, and the RTL issue closed; a WebView and an escape hatch for unwrapped native views; drag-and-drop primitives and a sliver-class list; more than one visible maintainer or the engine opened early; traction above noise (over 1,000 stars, community packages, one independent review); a stated position on iPhone Duo and iOS 27.

## 6. Decisions

| Question | Decision |
|---|---|
| Adopt DartNative | **No.** Recorded here and in `research/00-feasibility-summary.md` section 0 as a settled decision until the checkpoints above are met. |
| iPhone Duo readiness | Handle in Flutter per section 4; two small code items (`SideBySide` threshold, `DisplayCutout`) await Kelly's go-ahead and the Xcode 27.1 simulator. |
