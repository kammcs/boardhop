import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/features/projects/glass_shell_layout.dart';
import 'package:boardhop/features/shared/widgets/glass_navigation_rail.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
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

  final bodyKey = GlobalKey();
  EdgeInsets? seen;

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required EdgeInsets insets,
    bool bleed = false,
    bool onRight = true,
    CutoutSide cutout = CutoutSide.unknown,
  }) async {
    seen = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
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
          body: Builder(
            builder: (context) {
              seen = MediaQuery.paddingOf(context);
              return SizedBox.expand(key: bodyKey);
            },
          ),
        ),
      ),
    );
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

  testWidgets('portrait phone: the same bar, narrower, and whole at xxxL', (
    tester,
  ) async {
    // iPhone 17 in portrait: status bar and home indicator only.
    const portraitPhone = Size(402, 874);
    const portraitInsets = EdgeInsets.fromLTRB(0, 62, 0, 34);
    await pump(tester, size: portraitPhone, insets: portraitInsets);
    final r = rail(tester);
    expect(
      r.width,
      closeTo(portraitPhone.width * GlassShellLayout.heightFactor, 0.5),
    );
    expect(r.bottom, portraitPhone.height - 34 - GlassShellLayout.margin);
    expect(
      seen,
      const EdgeInsets.only(top: 62, bottom: 34 + GlassShellLayout.barGutter),
    );

    // At the largest accessibility size four scaled items would be wider
    // than the bar: they share its width instead of overflowing.
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, size: portraitPhone, insets: portraitInsets);
    expect(tester.takeException(), isNull);
    expect(
      rail(tester).width,
      closeTo(portraitPhone.width * GlassShellLayout.heightFactor, 0.5),
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
    expect(r.width, closeTo(tablet.width * GlassShellLayout.heightFactor, 0.5));
    expect(r.height, GlassNavigationRail.thickness);
    expect(r.bottom, tablet.height - 20 - GlassShellLayout.margin);
    final b = body(tester);
    expect(b.left, 0);
    expect(b.right, tablet.width);
    expect(
      seen,
      const EdgeInsets.only(top: 24, bottom: 20 + GlassShellLayout.barGutter),
    );
  });
}
