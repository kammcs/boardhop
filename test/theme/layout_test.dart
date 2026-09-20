import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/theme/layout.dart';
import 'package:boardhop/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/duo_display.dart';

void main() {
  test('content column follows the window up to the wide cap', () {
    expect(ContentColumn.widthFor(400), 400);
    expect(ContentColumn.widthFor(840), 840);
    // Grows with the window, keeping a margin on each side.
    expect(ContentColumn.widthFor(900), 852);
    expect(ContentColumn.widthFor(1032), 984);
    // iPad Pro 13" in landscape beside the rail: capped at the wide value.
    expect(ContentColumn.widthFor(1264), ContentColumn.wide);
    expect(ContentColumn.widthFor(2000), ContentColumn.wide);
  });

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SideBySide(start: [Text('start')], end: [Text('end')]),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('side by side sits in two columns when wide', (tester) async {
    await pump(tester, 1200);
    final start = tester.getTopLeft(find.text('start'));
    final end = tester.getTopLeft(find.text('end'));
    expect(start.dy, end.dy);
    expect(end.dx, greaterThan(start.dx + 400));
  });

  testWidgets('side by side stacks when narrow', (tester) async {
    await pump(tester, 600);
    final start = tester.getTopLeft(find.text('start'));
    final end = tester.getTopLeft(find.text('end'));
    expect(start.dx, end.dx);
    expect(end.dy, greaterThan(start.dy));
  });

  group('chartAxis', () {
    test('rounds the maximum up so no label is a headroom value', () {
      // The numbers the D-D walkthrough found on the device: nine items
      // read 9.9, seventeen read 18.7, a bar of two read 2.3.
      expect(chartAxis(9, integral: true).max, 10);
      expect(chartAxis(17, integral: true).max, 20);
      expect(chartAxis(2, integral: true).max, 2);
      expect(chartAxis(45, integral: true).max, 50);
      expect(chartAxis(70.5, integral: true).max, 80);
    });

    test('keeps whole-number intervals for counts', () {
      for (final data in [1, 3, 9, 17, 45, 121, 1003]) {
        final axis = chartAxis(data.toDouble(), integral: true);
        expect(axis.interval, axis.interval.roundToDouble());
        expect(axis.interval, greaterThanOrEqualTo(1));
        expect(axis.max, greaterThanOrEqualTo(data.toDouble()));
        expect(axis.max / axis.interval, lessThanOrEqualTo(5.0));
      }
    });

    test('allows fractional intervals for a measurement', () {
      final axis = chartAxis(0.4);
      expect(axis.max, closeTo(0.4, 1e-9));
      expect(axis.interval, closeTo(0.1, 1e-9));
    });

    test('strict keeps the data off the top edge', () {
      // A scatter dot has a radius, so a point exactly on the maximum is
      // drawn half outside the plot area.
      expect(chartAxis(0.4, strict: true).max, closeTo(0.5, 1e-9));
      expect(chartAxis(10, strict: true).max, greaterThan(10));
      expect(chartAxis(0, strict: true).max, greaterThan(0));
      expect(chartAxis(9, strict: true).max, greaterThan(9));
    });

    test('a maximum already on a step gains no empty division', () {
      expect(chartAxis(10, integral: true).max, 10);
      expect(chartAxis(20, integral: true).max, 20);
      expect(chartAxis(100, integral: true).max, 100);
    });

    test('degenerate data still gives a drawable axis', () {
      expect(chartAxis(0).max, 1);
      expect(chartAxis(-3).max, 1);
      expect(chartAxis(double.nan).max, 1);
      expect(chartAxis(double.infinity).max, 1);
    });

    test('the top label is dropped, and reliably', () {
      final axis = chartAxis(9, integral: true);
      expect(axis.showsLabel(0), isTrue);
      expect(axis.showsLabel(8), isTrue);
      expect(axis.showsLabel(10), isFalse);
      // The generated values accumulate rounding; an epsilon below the
      // maximum must still count as the top label (the "9.9" defect).
      expect(axis.showsLabel(10 - 1e-9), isFalse);
      expect(axis.showsLabel(-1), isFalse);
    });

    test('labels carry exactly the precision the interval needs', () {
      // A shared one-decimal formatter printed the gridline at 0.25 as
      // "0.3" and the one at 0.75 as "0.8" — numbers the axis was not
      // drawing (D-D walkthrough).
      final quarters = chartAxis(1, strict: true);
      expect(quarters.interval, closeTo(0.25, 1e-9));
      expect(
        [for (var i = 0; i <= 4; i++) quarters.label(i * quarters.interval)],
        ['0', '0.25', '0.5', '0.75', '1'],
      );
      final whole = chartAxis(9, integral: true);
      expect(
        [for (var i = 0; i <= 5; i++) whole.label(i * whole.interval)],
        ['0', '2', '4', '6', '8', '10'],
      );
    });

    test('fewer gridlines as the text grows', () {
      expect(axisTicks(1), 5);
      expect(axisTicks(1.6), 3);
    });

    test('chart insets leave the last x label room for its own half', () {
      expect(chartInsets(1).right, greaterThan(Spacing.sm));
      expect(chartInsets(1.6).right, greaterThan(chartInsets(1).right));
    });
  });

  // ------------------------------------------------------- the crease
  //
  // research/23 D3: half folded, the display is two regions and the
  // layout's boundaries land on the fold.

  group('paneWidthFor', () {
    test('follows the fraction when nothing is folded', () {
      expect(
        paneWidthFor(maxWidth: 867, fraction: 0.42, min: 320, max: 480),
        closeTo(364.14, 0.01),
      );
      // Clamped at both ends.
      expect(
        paneWidthFor(maxWidth: 600, fraction: 0.42, min: 320, max: 480),
        320,
      );
      expect(
        paneWidthFor(maxWidth: 2000, fraction: 0.42, min: 320, max: 480),
        480,
      );
    });

    test('takes the band\'s leading edge when the crease is in range', () {
      // The Duo's wide pose as a page sees it: the shell keeps 84 pt for
      // the system's bar column, so the crease is at 455.5 of 867 — not at
      // the box's own centre.
      const band = Rect.fromLTWH(455.5, 0, 40, 669);
      expect(
        paneWidthFor(
          maxWidth: 867,
          fraction: 0.42,
          min: 320,
          max: 480,
          creaseBand: band,
        ),
        455.5,
      );
    });

    test('ignores a crease outside the pane\'s range', () {
      // A 200 pt list pane is worse than a divider off the fold.
      const band = Rect.fromLTWH(200, 0, 40, 669);
      expect(
        paneWidthFor(
          maxWidth: 867,
          fraction: 0.42,
          min: 320,
          max: 480,
          creaseBand: band,
        ),
        closeTo(364.14, 0.01),
      );
    });

    test('ignores a horizontal crease', () {
      const band = Rect.fromLTWH(0, 455.5, 669, 40);
      expect(isVerticalCrease(band), isFalse);
      expect(
        paneWidthFor(
          maxWidth: 867,
          fraction: 0.42,
          min: 320,
          max: 480,
          creaseBand: band,
        ),
        closeTo(364.14, 0.01),
      );
    });

    test('the divider fills the band only when the pane is on it', () {
      const band = Rect.fromLTWH(455.5, 0, 40, 669);
      expect(paneDividerWidth(band, 455.5), 40);
      expect(paneDividerWidth(band, 364.14), 1);
      expect(paneDividerWidth(null, 455.5), 1);
    });
  });

  group('SideBySide on a crease', () {
    Future<void> pumpCrease(
      WidgetTester tester, {
      required Size window,
      DisplayRegions? regions,
    }) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Duo.scope(
          window: window,
          regions: regions,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: const [
                  SideBySide(start: [Text('start')], end: [Text('end')]),
                ],
              ),
            ),
          ),
        ),
      );
      // creaseInBox reads the transform the last layout left, so the first
      // build of a box answers null and asks for another frame.
      await tester.pump();
    }

    testWidgets('the boundary and the gap land on the fold', (tester) async {
      await pumpCrease(
        tester,
        window: Duo.wide,
        regions: Duo.folded(Duo.wideBand),
      );
      final start = tester.getTopLeft(find.text('start'));
      final end = tester.getTopLeft(find.text('end'));
      expect(start.dy, end.dy);
      // The end column starts on the far side of the keep-out band.
      expect(end.dx, closeTo(Duo.wideBand.right, 0.5));
      expect(start.dx, 0);
    });

    testWidgets('a display lying flat keeps today\'s split', (tester) async {
      // 951 is over twoColumnMin, so this is the ordinary flex split: two
      // equal columns with a Spacing.lg gap, not the fold's.
      await pumpCrease(
        tester,
        window: Duo.wide,
        regions: Duo.flat(Duo.wideBand),
      );
      final end = tester.getTopLeft(find.text('end'));
      expect(end.dx, closeTo((951 + Spacing.lg) / 2, 1));
    });

    testWidgets('a horizontal crease leaves it alone', (tester) async {
      await pumpCrease(
        tester,
        window: Duo.tall,
        regions: Duo.folded(Duo.tallBand),
      );
      // 669 is under twoColumnMin: stacked, as on any medium window.
      final start = tester.getTopLeft(find.text('start'));
      final end = tester.getTopLeft(find.text('end'));
      expect(start.dx, end.dx);
      expect(end.dy, greaterThan(start.dy));
    });
  });

  group('CreasePadding', () {
    /// The bottom inset the page below a [CreasePadding] is handed, in a
    /// box [height] tall with a band at [bandTop].
    Future<EdgeInsets> insetsFor(
      WidgetTester tester, {
      required Size window,
      required Rect band,
      EdgeInsets padding = EdgeInsets.zero,
    }) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late EdgeInsets seen;
      await tester.pumpWidget(
        Duo.scope(
          window: window,
          regions: Duo.folded(band),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: window, padding: padding),
              child: CreasePadding(
                child: Builder(
                  builder: (context) {
                    seen = MediaQuery.paddingOf(context);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return seen;
    }

    testWidgets('a band at the centre ends the content above it', (
      tester,
    ) async {
      final inset = await insetsFor(
        tester,
        window: Duo.tall,
        band: Duo.tallBand,
        padding: Duo.tallInsets,
      );
      // 951 - 455.5: the content's end rests on the fold's near edge.
      expect(inset.bottom, closeTo(495.5, 0.5));
      expect(inset.top, Duo.tallInsets.top);
    });

    testWidgets('a band near the top starts the content below it', (
      tester,
    ) async {
      final inset = await insetsFor(
        tester,
        window: Duo.tall,
        band: const Rect.fromLTWH(0, 40, 669, 40),
      );
      expect(inset.top, 80);
      expect(inset.bottom, 0);
    });

    testWidgets('a vertical crease changes nothing', (tester) async {
      final inset = await insetsFor(
        tester,
        window: Duo.wide,
        band: Duo.wideBand,
        padding: Duo.wideInsets,
      );
      expect(inset, Duo.wideInsets);
    });
  });

  group('ColumnSnapPhysics', () {
    test('rounds to the nearest rest position', () {
      // A 280 pt column with the 40 pt band as its gap, and a boundary on
      // the crease when the offset is 16 - 495.5.
      const physics = ColumnSnapPhysics(pitch: 320, origin: -479.5);
      // The lattice is … -159.5, 160.5, 480.5 … : the offsets at which a
      // column boundary lands on the crease.
      expect(physics.snap(150, min: 0, max: 2000), closeTo(160.5, 0.01));
      expect(physics.snap(300, min: 0, max: 2000), closeTo(160.5, 0.01));
      expect(physics.snap(400, min: 0, max: 2000), closeTo(480.5, 0.01));
      // Below the first rest position inside the extent it clamps rather
      // than scrolling backwards off the start.
      expect(physics.snap(0, min: 0, max: 2000), 0);
      // Every rest position is a whole number of pitches from the origin.
      for (final target in [77.0, 420.0, 1999.0]) {
        final snapped = physics.snap(target, min: 0, max: 4000);
        final steps = (snapped - physics.origin) / physics.pitch;
        expect(steps, closeTo(steps.roundToDouble(), 1e-9));
      }
    });

    test('never leaves the scrollable\'s own extent', () {
      const physics = ColumnSnapPhysics(pitch: 320, origin: -479.5);
      expect(physics.snap(-500, min: 0, max: 640), 0);
      expect(physics.snap(5000, min: 0, max: 640), 640);
    });

    test('a degenerate pitch is a no-op', () {
      const physics = ColumnSnapPhysics(pitch: 0, origin: 0);
      expect(physics.snap(123, min: 0, max: 2000), 123);
    });
  });
}
