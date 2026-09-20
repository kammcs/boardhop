import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/features/projects/glass_shell_layout.dart';
import 'package:boardhop/features/shared/widgets/glass_navigation_rail.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/theme_controller.dart' show RailSide;
import 'package:boardhop/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const destinations = [
    GlassRailDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    GlassRailDestination(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: 'Work',
    ),
    GlassRailDestination(
      icon: Icons.source_outlined,
      selectedIcon: Icons.source,
      label: 'Repos',
    ),
    GlassRailDestination(
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
      label: 'Pipelines',
    ),
  ];

  // iPhone 17 in landscape: 59 pt on each side for the Dynamic Island and
  // the corners, 21 pt for the home indicator.
  const phone = Size(874, 402);
  const phoneInsets = EdgeInsets.fromLTRB(59, 0, 59, 21);
  // iPad Pro 13" in portrait: status bar and home indicator only.
  const tablet = Size(1032, 1376);
  const tabletInsets = EdgeInsets.fromLTRB(0, 24, 0, 20);
  // iPhone Duo, measured 2026-09-20 (research/23 section 2). The inner
  // display in the wide pose, the cover in portrait, and a Split View half;
  // in each the stacked status bar takes 84 pt of the trailing edge and
  // reports the corner it really occupies as an active occlusion.
  const inner = Size(951, 669);
  const innerInsets = EdgeInsets.fromLTRB(0, 0, 84, 34);
  const innerStatusBar = Rect.fromLTWH(867, 0, 84, 120);
  const cover = Size(466, 678);
  const coverInsets = EdgeInsets.fromLTRB(0, 0, 84, 34);
  const coverStatusBar = Rect.fromLTWH(382, 0, 84, 170);
  const pane = Size(475, 669);
  // The tall pose, half folded: the crease runs across the window with
  // 20 pt of keep-out on each side of it.
  const tallCrease = Rect.fromLTWH(0, 455.5, 669, 40);

  final bodyKey = GlobalKey();
  EdgeInsets? seen;

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required EdgeInsets insets,
    bool bleed = false,
    bool onRight = true,
    CutoutSide cutout = CutoutSide.unknown,
    double keyboard = 0,
    RailSide? systemSide,
    List<Rect> occlusions = const [],
    Rect? creaseBand,
    Axis? creaseAxis,
  }) async {
    seen = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.view.padding = FakeViewPadding(
      left: insets.left,
      top: insets.top,
      right: insets.right,
      bottom: insets.bottom,
    );
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: GlassShellLayout(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          bleedsUnderRail: bleed,
          railOnRight: onRight,
          cutoutSide: cutout,
          systemRailSide: systemSide,
          occlusions: occlusions,
          creaseBand: creaseBand,
          creaseAxis: creaseAxis,
          body: Builder(
            builder: (context) {
              seen = MediaQuery.paddingOf(context);
              return SizedBox.expand(key: bodyKey);
            },
          ),
        ),
      ),
    );
    // The rail's box and the page's gutter are implicitly animated now
    // (research/23 D7), so a second pump in the same test lands mid-flight
    // unless it is let settle. Every assertion below is about where things
    // come to rest.
    await tester.pumpAndSettle();
  }

  Rect rail(WidgetTester tester) =>
      tester.getRect(find.byType(GlassNavigationRail));
  Rect body(WidgetTester tester) => tester.getRect(find.byKey(bodyKey));

  testWidgets('landscape phone, island side unknown: full-width rail '
      'outside the side inset', (tester) async {
    await pump(tester, size: phone, insets: phoneInsets);
    final r = rail(tester);
    expect(r.width, GlassNavigationRail.width);
    expect(r.right, phone.width - 59 - GlassShellLayout.margin);
    // Four fifths of the safe height, centered in it.
    const safeHeight = 402 - 21;
    expect(r.height, closeTo(safeHeight * GlassShellLayout.heightFactor, 0.5));
    expect(r.center.dy, closeTo(safeHeight / 2, 0.5));

    // The page keeps clear of both sides and of the rail.
    final b = body(tester);
    expect(b.left, 59);
    expect(b.right, phone.width - 59 - GlassShellLayout.railGutter);
    expect(seen, const EdgeInsets.only(bottom: 21));
  });

  testWidgets('island on the other side: the rail keeps only its margin '
      'from the edge', (tester) async {
    await pump(
      tester,
      size: phone,
      insets: phoneInsets,
      cutout: CutoutSide.left,
    );
    final r = rail(tester);
    expect(r.width, GlassNavigationRail.width);
    expect(r.right, phone.width - GlassShellLayout.margin);
    final b = body(tester);
    expect(b.left, 59);
    expect(b.right, phone.width - GlassShellLayout.railGutter);

    // The board too: its padding on the rail side is measured from the edge.
    await pump(
      tester,
      size: phone,
      insets: phoneInsets,
      cutout: CutoutSide.left,
      bleed: true,
    );
    expect(
      seen,
      const EdgeInsets.fromLTRB(59, 0, GlassShellLayout.railGutter, 21),
    );

    // Rail on the left with the island on the right: mirrored.
    await pump(
      tester,
      size: phone,
      insets: phoneInsets,
      cutout: CutoutSide.right,
      onRight: false,
    );
    expect(rail(tester).left, GlassShellLayout.margin);
    expect(body(tester).left, GlassShellLayout.railGutter);
  });

  testWidgets('island on the rail side: the rail clears the inset', (
    tester,
  ) async {
    await pump(
      tester,
      size: phone,
      insets: phoneInsets,
      cutout: CutoutSide.right,
    );
    expect(rail(tester).right, phone.width - 59 - GlassShellLayout.margin);
    expect(body(tester).right, phone.width - 59 - GlassShellLayout.railGutter);
  });

  testWidgets('landscape rail on the left', (tester) async {
    await pump(tester, size: phone, insets: phoneInsets, onRight: false);
    expect(rail(tester).left, 59 + GlassShellLayout.margin);
    final b = body(tester);
    expect(b.left, 59 + GlassShellLayout.railGutter);
    expect(b.right, phone.width - 59);
  });

  testWidgets('a sideways scroller runs under the rail with the gutter '
      'as padding', (tester) async {
    await pump(tester, size: phone, insets: phoneInsets, bleed: true);
    final b = body(tester);
    expect(b.left, 0);
    expect(b.right, phone.width);
    expect(
      seen,
      const EdgeInsets.fromLTRB(59, 0, 59 + GlassShellLayout.railGutter, 21),
    );
  });

  testWidgets('portrait phone: a tab bar Apple\'s size, low on the screen', (
    tester,
  ) async {
    // iPhone 17 in portrait: status bar and home indicator only.
    const portraitPhone = Size(402, 874);
    const portraitInsets = EdgeInsets.fromLTRB(0, 62, 0, 34);
    await pump(tester, size: portraitPhone, insets: portraitInsets);
    final r = rail(tester);
    // A phone keeps Apple's fixed side margin, not a fraction of the
    // width, and the bar is 56 pt tall like Apple's own.
    expect(r.width, portraitPhone.width - 2 * GlassShellLayout.barSideMargin);
    expect(r.height, GlassNavigationRail.thickness);
    expect(r.bottom, portraitPhone.height - GlassShellLayout.barBottomMargin);
    // The point of that margin: the bar sits over the home-indicator
    // band rather than above it, which left it floating far too high
    // (Kelly, 2026-09-12).
    expect(r.bottom, greaterThan(portraitPhone.height - portraitInsets.bottom));
    // The page's bottom padding is measured from the screen's edge, so it
    // replaces the home-indicator inset instead of adding to it, and it
    // clears the whole bar.
    expect(
      seen,
      const EdgeInsets.only(top: 62, bottom: GlassShellLayout.barGutter),
    );
    expect(portraitPhone.height - seen!.bottom, lessThan(r.top));

    // At the largest accessibility size four scaled items would be wider
    // than the bar: they share its width instead of overflowing.
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, size: portraitPhone, insets: portraitInsets);
    expect(tester.takeException(), isNull);
    expect(
      rail(tester).width,
      portraitPhone.width - 2 * GlassShellLayout.barSideMargin,
    );
    for (final label in ['Home', 'Work', 'Repos', 'Pipelines']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('portrait tablet: bar along the bottom, page padded above it', (
    tester,
  ) async {
    await pump(tester, size: tablet, insets: tabletInsets);
    final r = rail(tester);
    // A tablet keeps the fraction of the width: a bar 22 pt off each side
    // of an iPad reads as a slab.
    expect(r.width, closeTo(tablet.width * GlassShellLayout.heightFactor, 0.5));
    expect(r.height, GlassNavigationRail.thickness);
    expect(r.bottom, tablet.height - GlassShellLayout.barBottomMargin);
    final b = body(tester);
    expect(b.left, 0);
    expect(b.right, tablet.width);
    expect(
      seen,
      const EdgeInsets.only(top: 24, bottom: GlassShellLayout.barGutter),
    );
  });

  testWidgets('the keyboard covers the bar, and shortens the page above it', (
    tester,
  ) async {
    // A focused field on the iPad reported a 400 pt keyboard inset and the
    // shell's Scaffold raised the whole stack, dock included, above it
    // (2026-09-14). Apple's tab bar stays put under the keyboard.
    await pump(tester, size: tablet, insets: tabletInsets, keyboard: 400);
    final r = rail(tester);
    expect(r.bottom, tablet.height - GlassShellLayout.barBottomMargin);

    // The page's own box is what shrinks. A `Scaffold` never lifts its
    // `bottomNavigationBar` on its own — the box it is given does — so
    // without this every composer anchored that way (the work item
    // Discussion box, research/16 M1) sat behind the keyboard.
    final b = body(tester);
    expect(b.bottom, tablet.height - 400);
    // And having taken the inset off the box, the shell takes it off the
    // media query too, so the page does not count it twice.
    final insets = MediaQuery.viewInsetsOf(tester.element(find.byKey(bodyKey)));
    expect(insets.bottom, 0);
    // With the bar behind the keyboard there is nothing left to clear: the
    // page keeps the real inset only. (iOS itself zeroes `padding.bottom`
    // while the keyboard is up; this fake view keeps its 20.)
    expect(seen, const EdgeInsets.only(top: 24, bottom: 20));
  });

  // The iPhone Duo (research/23 phase 2). Wherever iOS names the edge its
  // own vertical bar belongs on, the rail moves *into* the column iOS has
  // reserved there and drops its glass pill: bare destinations lined up
  // under the stacked status cluster, as Apple's vertical tab bar is.

  Finder glass(WidgetTester tester) => find.descendant(
    of: find.byType(GlassNavigationRail),
    matching: find.byType(BackdropFilter),
  );

  testWidgets('the system edge: a bare column in the reserved 84 pt, under '
      'the status cluster', (tester) async {
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
    );
    final r = rail(tester);
    expect(r.width, GlassNavigationRail.width);
    // Lined up on the cluster's own x (909 = the centre of the reserved
    // column), not hugging the screen edge.
    expect(r.center.dx, innerStatusBar.center.dx);
    expect(
      tester.getCenter(find.byIcon(Icons.home)).dx,
      innerStatusBar.center.dx,
    );
    // No glass: no blur, and so no container, tint, hairline or shadow.
    expect(glass(tester), findsNothing);
    // As long as its destinations and their gaps, centered in what is left
    // below the cluster — not four fifths of the window.
    const top = 120.0;
    const bottom = 669 - 34.0;
    expect(r.top, greaterThanOrEqualTo(top));
    expect(r.height, closeTo(4 * 50 + 3 * GlassNavigationRail.bareGap, 0.5));
    expect(r.center.dy, closeTo((top + bottom) / 2, 0.5));

    // The page stops at the reserved column and no further: 867 pt of it.
    final b = body(tester);
    expect(b.left, 0);
    expect(b.width, 867);
    expect(seen, const EdgeInsets.only(bottom: 34));
  });

  testWidgets('the system edge wins over the setting, and holds in portrait', (
    tester,
  ) async {
    // The cover display is compact *and* portrait — both of which would
    // have meant a bar along the bottom — and the setting asks for the
    // left. iOS says trailing, so the rail is a column on the right.
    await pump(
      tester,
      size: cover,
      insets: coverInsets,
      systemSide: RailSide.right,
      occlusions: const [coverStatusBar],
      onRight: false,
    );
    final r = rail(tester);
    expect(r.width, GlassNavigationRail.width);
    expect(r.center.dx, coverStatusBar.center.dx);
    expect(glass(tester), findsNothing);
    // 382 pt of page on a 466 pt cover, and the column starts below the
    // cover's taller cluster (170 pt).
    expect(body(tester).width, 382);
    const top = 170.0;
    const bottom = 678 - 34.0;
    expect(r.top, greaterThanOrEqualTo(top));
    expect(r.center.dy, closeTo((top + bottom) / 2, 0.5));

    // With no system edge the same window is the glass bar along the
    // bottom and the setting is back in charge.
    await pump(tester, size: cover, insets: coverInsets, onRight: false);
    expect(rail(tester).height, GlassNavigationRail.thickness);
    expect(glass(tester), findsOneWidget);
    await pump(tester, size: phone, insets: phoneInsets, onRight: false);
    expect(rail(tester).left, 59 + GlassShellLayout.margin);
    expect(glass(tester), findsOneWidget);
  });

  testWidgets('the leading edge', (tester) async {
    await pump(
      tester,
      size: inner,
      insets: const EdgeInsets.fromLTRB(84, 0, 0, 34),
      systemSide: RailSide.left,
      occlusions: const [Rect.fromLTWH(0, 0, 84, 120)],
    );
    expect(rail(tester).center.dx, 42);
    expect(rail(tester).top, greaterThanOrEqualTo(120));
    expect(body(tester).left, 84);
    expect(body(tester).width, 867);

    // The cover, the other way round.
    await pump(
      tester,
      size: cover,
      insets: const EdgeInsets.fromLTRB(84, 0, 0, 34),
      systemSide: RailSide.left,
      occlusions: const [Rect.fromLTWH(0, 0, 84, 170)],
    );
    expect(rail(tester).center.dx, 42);
    expect(body(tester).left, 84);
    expect(body(tester).width, 382);
  });

  testWidgets('a compact pane keeps the rail and its labels', (tester) async {
    // A Split View half of the inner display, on the outer edge. Split
    // View cannot be started from a script (research/23 section 9.5), so
    // this is the only check of it.
    await pump(
      tester,
      size: pane,
      insets: const EdgeInsets.fromLTRB(0, 0, 84, 34),
      systemSide: RailSide.right,
      occlusions: const [Rect.fromLTWH(391, 0, 84, 120)],
    );
    final r = rail(tester);
    // Full width and every label: the capsule behind icon *and* label is a
    // settled rule, and the column is the system's own either way.
    expect(r.width, GlassNavigationRail.width);
    for (final label in ['Home', 'Work', 'Repos', 'Pipelines']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(r.center.dx, 433);
    expect(body(tester).width, 391);

    // An edge with nothing reserved on it: the column is the rail's own
    // width and it centers in that.
    await pump(
      tester,
      size: pane,
      insets: const EdgeInsets.fromLTRB(0, 0, 0, 34),
      systemSide: RailSide.right,
    );
    expect(rail(tester).center.dx, pane.width - GlassNavigationRail.width / 2);
    expect(body(tester).width, pane.width - GlassNavigationRail.width);
  });

  testWidgets('an active horizontal crease: the rail stays in the lower '
      'half', (tester) async {
    await pump(
      tester,
      size: const Size(669, 951),
      insets: const EdgeInsets.fromLTRB(0, 82, 0, 34),
      systemSide: RailSide.right,
      creaseBand: tallCrease,
      creaseAxis: Axis.horizontal,
    );
    final r = rail(tester);
    // Never across the fold, and clear of its 20 pt keep-out margin: the
    // band ends at 495.5.
    expect(r.top, greaterThanOrEqualTo(tallCrease.bottom));
    const bottom = 951 - 34.0;
    expect(r.center.dy, closeTo((tallCrease.bottom + bottom) / 2, 0.5));

    // With no system edge the same pose keeps the bar along the bottom,
    // which is in the lower half already.
    await pump(
      tester,
      size: const Size(669, 951),
      insets: const EdgeInsets.fromLTRB(0, 82, 0, 34),
      creaseBand: tallCrease,
      creaseAxis: Axis.horizontal,
    );
    expect(rail(tester).bottom, 951 - GlassShellLayout.barBottomMargin);

    // A vertical crease is beside the rail, not under it: nothing moves.
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
      creaseBand: const Rect.fromLTWH(455.5, 0, 40, 669),
      creaseAxis: Axis.vertical,
    );
    expect(rail(tester).center.dx, innerStatusBar.center.dx);
    expect(rail(tester).top, greaterThanOrEqualTo(120));
  });

  testWidgets('a sideways scroller on the system edge gets the column as '
      'padding', (tester) async {
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
      bleed: true,
    );
    expect(body(tester).width, inner.width);
    expect(seen, const EdgeInsets.fromLTRB(0, 0, 84, 34));
  });

  testWidgets('at an accessibility text size the column stays on screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
    );
    final r = rail(tester);
    // Wider than the 84 pt iOS reserved, so it is held inside the window
    // and the page gives it the room instead of being drawn under it.
    expect(r.width, GlassNavigationRail.width * GlassNavigationRail.maxScale);
    expect(r.right, inner.width);
    expect(body(tester).right, r.left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page fades out at the column, and only there', (
    tester,
  ) async {
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
    );
    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect(mask.blendMode, BlendMode.dstIn);
    // Whole up to 12 pt before the column, gone from its inner boundary
    // (867) on, so nothing shows under the destinations or the cluster.
    final fade = GlassShellLayout.columnFade(
      width: inner.width,
      column: 84,
      onRight: true,
    );
    expect(fade.stops!.map((s) => s * inner.width), [
      0,
      closeTo(867 - GlassShellLayout.fadeWidth, 0.01),
      closeTo(867, 0.01),
      inner.width,
    ]);
    expect(fade.colors.first.a, 1);
    expect(fade.colors.last.a, 0);

    // The leading edge is the mirror: gone up to the boundary at 84.
    final leading = GlassShellLayout.columnFade(
      width: inner.width,
      column: 84,
      onRight: false,
    );
    expect(leading.colors.first.a, 0);
    expect(leading.colors.last.a, 1);
    expect(leading.stops!.map((s) => s * inner.width), [
      0,
      closeTo(84, 0.01),
      closeTo(84 + GlassShellLayout.fadeWidth, 0.01),
      inner.width,
    ]);

    // A sideways scroller is masked too: it keeps scrolling under the
    // column, it is simply not seen there.
    await pump(
      tester,
      size: inner,
      insets: innerInsets,
      systemSide: RailSide.right,
      occlusions: const [innerStatusBar],
      bleed: true,
    );
    expect(find.byType(ShaderMask), findsOneWidget);

    // No system edge, no mask: the glass pill has its own backdrop.
    await pump(tester, size: phone, insets: phoneInsets);
    expect(find.byType(ShaderMask), findsNothing);
    await pump(tester, size: cover, insets: coverInsets);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('a window too short for the rail does not squeeze it', (
    tester,
  ) async {
    // The Duo reports a window about 140 pt tall for a frame while it
    // switches panels, and four fifths of that is less than the
    // destinations need: the rail overflowed by 77 px in the debug log
    // (2026-09-20). It keeps its own length instead.
    await pump(
      tester,
      size: const Size(951, 140),
      insets: const EdgeInsets.fromLTRB(0, 0, 0, 0),
    );
    expect(tester.takeException(), isNull);
    expect(
      rail(tester).height,
      greaterThanOrEqualTo(4 * 50 + 2 * Spacing.sm - 0.5),
    );
  });

  testWidgets('the rail slides between the bar and the edge', (tester) async {
    // A fold or a rotation moves the rail without a frame of the wrong
    // layout: it is laid out at the size it is heading for the whole way
    // (research/23 D7).
    await pump(tester, size: cover, insets: coverInsets);
    final bar = rail(tester);
    expect(bar.height, GlassNavigationRail.thickness);

    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: GlassShellLayout(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          bleedsUnderRail: false,
          railOnRight: true,
          systemRailSide: RailSide.right,
          occlusions: const [coverStatusBar],
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    final moving = rail(tester);
    // Already the column's width, and on its way across and up.
    expect(moving.width, GlassNavigationRail.width);
    expect(moving.center.dx, greaterThan(bar.center.dx));
    expect(moving.center.dy, lessThan(bar.center.dy));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(rail(tester).center.dx, coverStatusBar.center.dx);
  });

  testWidgets('landscape: the rail ignores the keyboard too', (tester) async {
    await pump(tester, size: phone, insets: phoneInsets);
    final without = rail(tester);
    await pump(tester, size: phone, insets: phoneInsets, keyboard: 300);
    expect(rail(tester), without);
    // The page shrinks and the inset is spent, in this branch as well.
    expect(body(tester).bottom, phone.height - 300);
    final insets = MediaQuery.viewInsetsOf(tester.element(find.byKey(bodyKey)));
    expect(insets.bottom, 0);
  });
}
