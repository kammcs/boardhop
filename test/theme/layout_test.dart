import 'package:boardhop/theme/layout.dart';
import 'package:boardhop/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
