import 'package:boardhop/features/shared/widgets/glass_navigation_rail.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    required ValueChanged<int> onSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GlassNavigationRail(
              destinations: destinations,
              selectedIndex: 1,
              onDestinationSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('is sized to its destinations and reports taps', (tester) async {
    int? tapped;
    await pump(
      tester,
      theme: BoardhopTheme.light(),
      onSelected: (i) => tapped = i,
    );

    for (final d in destinations) {
      expect(find.text(d.label), findsOneWidget);
    }
    final size = tester.getSize(find.byType(GlassNavigationRail));
    expect(size.width, GlassNavigationRail.width);
    expect(size.height, lessThan(tester.view.physicalSize.height / 2));

    await tester.tap(find.text('Pipelines'));
    expect(tapped, 3);

    // Exactly one destination carries the selected flag.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.assignment), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('spread mode fills the given height and spaces items out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 560,
              child: GlassNavigationRail(
                spread: true,
                destinations: destinations,
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(GlassNavigationRail)).height, 560);
    final first = tester.getCenter(find.text('Home'));
    final last = tester.getCenter(find.text('Pipelines'));
    // Four items spread evenly over 560 px sit far further apart than the
    // ~70 px of a packed rail.
    expect((last.dy - first.dy) / 3, greaterThan(100));
  });

  testWidgets('spread mode takes a minimum length and grows only for its items', (
    tester,
  ) async {
    Future<double> heightHeldTo(double minHeight) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: GlassNavigationRail(
                  spread: true,
                  destinations: destinations,
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(GlassNavigationRail)).height;
    }

    // The shell holds the rail to 80% of the screen: it takes exactly that.
    expect(await heightHeldTo(400), 400);
    // Held to less than its destinations need, it stays as tall as they
    // are (large text on a phone in landscape) rather than overflowing.
    final packed = await heightHeldTo(0);
    expect(packed, greaterThan(100));
    expect(await heightHeldTo(100), packed);
  });

  testWidgets('horizontal spread mode fills the given width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 640,
              child: GlassNavigationRail(
                axis: Axis.horizontal,
                spread: true,
                destinations: destinations,
                selectedIndex: 2,
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(GlassNavigationRail));
    expect(size.width, 640);
    expect(size.height, GlassNavigationRail.thickness);
    final first = tester.getCenter(find.text('Home'));
    final last = tester.getCenter(find.text('Pipelines'));
    expect(first.dy, last.dy);
    expect((last.dx - first.dx) / 3, greaterThan(120));

    // The destinations share the bar and each sits in the middle of its
    // own slot. A width set on the item's Stack rather than on its
    // content let the icon and label shrink to their own size and pin to
    // the left of the slot, so the first tab crowded the bar's left end
    // (2026-09-12).
    final bar = tester.getRect(find.byType(GlassNavigationRail));
    final slot =
        (bar.width - 2 * GlassNavigationRail.barInset) / destinations.length;
    for (var i = 0; i < destinations.length; i++) {
      final wanted = bar.left + GlassNavigationRail.barInset + slot * (i + 0.5);
      for (final finder in [
        find.text(destinations[i].label),
        find.byIcon(destinations[i].icon),
        find.byIcon(destinations[i].selectedIcon),
      ]) {
        if (finder.evaluate().isEmpty) continue;
        expect(
          tester.getCenter(finder).dx,
          closeTo(wanted, 0.5),
          reason: '${destinations[i].label} is not centred in its slot',
        );
      }
    }
  });

  testWidgets('at accessibility text sizes the rail grows and the label '
      'stays whole', (tester) async {
    Future<Size> railAt(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: GlassNavigationRail(
                  destinations: destinations,
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(GlassNavigationRail));
    }

    final normal = await railAt(1);
    expect(normal.width, GlassNavigationRail.width);

    // xxxL: the rail follows the text scale up to its cap, and the widest
    // label is laid out whole inside it instead of reading "Pipelin…".
    final huge = await railAt(3.1);
    expect(huge.width, GlassNavigationRail.width * GlassNavigationRail.maxScale);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Pipelines'),
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'no "Pipelin…"');
    // Painted (so after the scale-down) it fits inside the rail.
    final rect = tester.getRect(find.text('Pipelines'));
    expect(rect.width, lessThanOrEqualTo(huge.width));
  });

  testWidgets('builds in dark mode too', (tester) async {
    await pump(tester, theme: BoardhopTheme.dark(), onSelected: (_) {});
    expect(find.byType(GlassNavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
