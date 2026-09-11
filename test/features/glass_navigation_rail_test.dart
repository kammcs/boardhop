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
  });

  testWidgets('builds in dark mode too', (tester) async {
    await pump(tester, theme: BoardhopTheme.dark(), onSelected: (_) {});
    expect(find.byType(GlassNavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
