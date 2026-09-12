# Boardhop design ground rules

Locked 2026-09-10, before the feature screens. Everything visual flows from one place, `lib/theme/`, which `main.dart` loads before the first frame and hands to `MaterialApp`. Screens inherit; they do not restyle.

## 1. One master theme

- `BoardhopTheme.light()` and `BoardhopTheme.dark()` in [lib/theme/boardhop_theme.dart](lib/theme/boardhop_theme.dart) are the only `ThemeData` in the app. Both are built once in `BoardhopApp` and never rebuilt.
- The scheme is seeded from a neutral slate (`BoardhopTheme.seed`) with Material 3's `neutral` variant, so app chrome is quiet grey in both modes. That is deliberate: the saturated colors on screen are the ones that carry meaning, whether a team's lane and column colors from Azure DevOps or the status palette in `BoardhopColors`, and a strong brand hue would compete with them. It also keeps us visually distinct from Microsoft's blue (research/07). Change the seed or variant in one place and every screen follows.
- Component looks (app bar, cards, list tiles, buttons, inputs, chips, sheets, dialogs, snackbars, navigation bar and rail) are set in the theme's component blocks. If a widget needs a different look on one screen, the fix goes into the theme, not the screen.
- Buttons keep the theme's 48×48 minimum; a full-width call to action gets its width from a stretched `Column` or a `ListView`, never from `Size.fromHeight` in a style (an infinite minimum width is an invalid constraint inside a `Row`).
- `ThemeData` is Material 3 with the platform defaults for transitions, so iOS gets Cupertino navigation feel. Use the `.adaptive` constructors where Flutter offers them: `Switch.adaptive`, `Slider.adaptive`, `CircularProgressIndicator.adaptive`, `AlertDialog.adaptive`.

## 2. Light and dark

- Both modes are first class. Nothing is designed light-first and patched for dark.
- Mode follows the system setting by default. `ThemeController` (persisted with `shared_preferences`) exposes system / light / dark; Settings > Appearance lets the user pin one. The controller is loaded in `main` before `runApp` so there is no flash of the wrong mode.
- Screens never branch on brightness. If something must differ between modes, it becomes a token in `BoardhopColors` with a light and a dark value.

## 3. Colors: only through the theme

- Never write `Colors.*` or a hex literal in a screen or widget. Use `Theme.of(context).colorScheme.*` for UI chrome and `context.boardhopColors.*` for Azure DevOps semantics.
- `BoardhopColors` ([lib/theme/boardhop_colors.dart](lib/theme/boardhop_colors.dart)) is a `ThemeExtension` carrying the domain palette: work item types (bug, task, story, feature, epic, issue, test case), state categories (proposed, in progress, resolved, completed, removed), pull request status and reviewer votes, pipeline run outcomes, diff added/removed, and code background. Each has a light and a dark value tuned for contrast on our surfaces. Use `workItemType(name)` and `stateCategory(category)` rather than matching strings in widgets.
- Azure DevOps lets teams recolor work item types and board columns. When the API supplies a color (work item type `color`, board column settings), render that; fall back to `BoardhopColors` only when the API has none. Tint API colors for dark mode with `Color.lerp` toward the surface instead of using them raw.
- Status is never carried by color alone. Pair every colored indicator with an icon or a label (state chips have text, vote icons have tooltips, run outcomes have icons).

## 4. Type

- System font on each platform (Roboto on Android, SF on iOS). No bundled display face for v1.
- Use the `TextTheme` roles: `titleLarge` for app bar titles, `titleMedium` for card and section titles, `bodyLarge` for primary list text, `bodyMedium` for secondary, `labelMedium` for chips and metadata, `bodySmall` for timestamps. No ad hoc font sizes.
- Code, diffs, IDs and diagnostics use `BoardhopTheme.codeStyle(context)`.
- Respect the user's text scale. Layouts must survive 130% text without clipping; use `Flexible`, wrapping, and `maxLines` with ellipsis rather than fixed heights.

## 5. Spacing, shape, motion

- Spacing comes from `Spacing` in [lib/theme/tokens.dart](lib/theme/tokens.dart): 4, 8, 12, 16, 24, 32. Page gutter is 16. No other paddings.
- Corner radii from `Radii`: 8 for chips, 12 for cards, buttons and inputs, 16 for sheets and dialogs.
- Touch targets are at least 48 dp on both platforms (`kMinTapTarget`); the theme sets this on buttons.
- Motion uses `Durations.fast` / `normal` / `slow` (120 / 220 / 360 ms). Prefer implicit animations (`AnimatedSwitcher`, `AnimatedContainer`) and platform page transitions over custom ones.

## 6. Layout: phones first, tablets not an afterthought

- `Breakpoint` in [lib/theme/layout.dart](lib/theme/layout.dart) follows Material window size classes: compact (< 600), medium (< 840), expanded. Read it with `context.breakpoint`.
- Every screen works at compact width. On medium and expanded, wrap scrolling content in `ContentColumn`: it follows the window up to 1120 dp (840 alone left a third of an iPad in landscape empty), and pages with distinct sections put them in two columns with `SideBySide` from 960 dp of content width (Home, repo page, PR overview). Use the extra width for a second pane where it helps (list + detail for work items and PRs, `NavigationRail` instead of `NavigationBar`). That is the "responsive tablet layout" decision from research/00; multi-pane is a later milestone, but nothing built now may assume a phone.
- Keep the primary action reachable with one thumb: bottom-anchored buttons and sheets on phones, not top-right only.

## 7. Components and patterns

- Tablet navigation: on iOS and macOS the project shell uses `GlassNavigationRail` (a floating Liquid Glass pill centered on the right by default, or the left via Settings > Appearance, spanning about 80% of the height with the destinations spread evenly along it; vertical pages are padded clear of it, while sideways scrollers such as the Kanban board get the gutter as left `MediaQuery` padding, rest clear of the rail and slide under it when scrolled, showing through a blur with a saturation boost, a thin surface tint, a specular top highlight and a soft shadow; `Radii.xl` corners. In portrait the same rail lies along the bottom at 80% of the width, and pages get its height as bottom safe-area padding, so vertical content scrolls under it and its end clears it. The page keeps clear of the display's sides with a `SafeArea` (a phone in landscape reports 59 dp on each side for the Dynamic Island and the corners) and the rail sits outside those insets as well. The inset is the same on both sides while the island is on one, so `DisplayCutout` (`lib/core`) asks the Runner for the interface orientation over the `com.kammcs.boardhop/display` channel and the rail keeps only its shadow margin from the island-free edge; the layout lives in `GlassShellLayout` with a test at phone and tablet insets); elsewhere the Material `NavigationRail`. iPhones get the same chrome: the bar along the bottom in portrait (its items share the width at large text sizes) and the rail in landscape; the Material `NavigationBar` remains Android's phone chrome. Every page outside the shell wraps its body in `SafeArea(top: false, bottom: false)`: `Scaffold` insets nothing on the sides, and an iPhone in landscape otherwise puts text under the island.
- Lists: `ListTile` inside `ListView` for navigation lists; `Card` only when an item has several lines of mixed content (work item cards on a board, PR summaries).
- Primary action: `FilledButton`. Secondary: `OutlinedButton` or `TextButton`. Never two filled buttons side by side.
- Loading: `LinearProgressIndicator` under the app bar for refreshes that keep stale content visible; `CircularProgressIndicator.adaptive` only for a truly empty screen.
- Errors: inline, near the content they concern, in `colorScheme.error`, with the Azure DevOps message shown verbatim where it helps the user or their admin (AADSTS codes, TF codes). Snackbars only for transient confirmations; one with an action passes `persist: false`, because Flutter 3.47 otherwise keeps it open until dismissed and every later snackbar queues behind it.
- Offline and queued writes (a settled decision) show a persistent, unobtrusive banner, not a dialog.
- Empty states have one sentence and, where possible, one action.

## 8. Accessibility

- Contrast: text and icons meet WCAG AA on their surface in both modes. `ColorScheme.fromSeed` guarantees this for scheme colors; `BoardhopColors` values were picked for it.
- Every icon-only button has a `tooltip`. Every image or status glyph has semantics.
- Dynamic type and screen readers are tested on the diagnostics screen before each milestone.

## 9. How to add a screen

1. Start from the nearest existing screen in `lib/features/`.
2. Read colors, text styles and spacing from the theme and tokens; no literals.
3. Check the screen at compact and expanded widths, in light and dark, at 130% text.
4. If the theme needs a change to make the screen right, change the theme, then the screen.
