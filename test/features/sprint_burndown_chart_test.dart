import 'package:boardhop/features/sprints/widgets/sprint_burndown_chart.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<BurndownDay> _days(List<int> remaining) => [
  for (var i = 0; i < remaining.length; i++)
    BurndownDay(
      date: DateTime.utc(2026, 9, 7).add(Duration(days: i)),
      remaining: remaining[i],
    ),
];

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? BoardhopTheme.light()
          : BoardhopTheme.dark(),
      home: Scaffold(body: SizedBox(width: 400, height: 400, child: child)),
    );

void main() {
  group('the ideal line is anchored on the sprint, not on the data (P-C)', () {
    // Analytics answers one row per day up to today, never to the end of
    // the sprint (P-A §8.4). Burning to zero over the rows in hand put the
    // ideal at zero four days into a fortnight, and the header then called
    // a sprint that was on schedule "2 items/day behind".
    final days = [
      for (var i = 0; i < 4; i++)
        BurndownDay(date: DateTime.utc(2026, 9, 12 + i), remaining: 16 - i),
    ];

    test('with a finish date the line has the slope it really has', () {
      final ideal = burndownIdealLine(days, finish: DateTime.utc(2026, 9, 21));

      // 16 on 12 Sep down to 0 on 21 Sep: nine days, so 16/9 a day.
      expect(ideal.first, 16);
      expect(ideal[1], closeTo(16 * 8 / 9, 0.001));
      expect(ideal.last, closeTo(16 * 6 / 9, 0.001));
      // And it never reaches zero inside the window the chart draws.
      expect(ideal.last, greaterThan(10));
    });

    test('without one it falls back to the old shape', () {
      // Three of the four puremedia projects run the stock undated
      // Iteration 1, so this path is not hypothetical.
      final ideal = burndownIdealLine(days);

      expect(ideal.first, 16);
      expect(ideal.last, 0);
    });

    test('a finish date already past clamps at zero rather than going '
        'negative', () {
      final ideal = burndownIdealLine(days, finish: DateTime.utc(2026, 9, 13));

      expect(ideal.first, 16);
      expect(ideal.last, 0);
      expect(ideal.every((v) => v >= 0), isTrue);
    });

    test('a finish date on the first day is no span at all, and the old '
        'shape answers', () {
      final ideal = burndownIdealLine(days, finish: DateTime.utc(2026, 9, 12));

      expect(ideal.last, 0);
    });
  });

  group('burndownIdealLine', () {
    test('runs from the opening scope to zero', () {
      final line = burndownIdealLine(_days([10, 8, 6, 4]));
      expect(line, hasLength(4));
      expect(line.first, 10);
      expect(line.last, 0);
      expect(line[1], closeTo(6.667, 0.001));
    });

    test('is empty when there are no days at all', () {
      expect(burndownIdealLine(const []), isEmpty);
    });

    test('a one-day sprint is just its own scope', () {
      expect(burndownIdealLine(_days([10])), [10]);
    });
  });

  group('burndownSemanticsLabel', () {
    test('names the day, the remaining work and the ideal', () {
      final days = _days([10, 8, 6]);
      expect(
        burndownSemanticsLabel(days, ideal: burndownIdealLine(days)),
        'Sprint burndown. 6 items remaining on day 3 of 3. Ideal 0 items.',
      );
    });

    test('says so when there is no data', () {
      expect(burndownSemanticsLabel(const []), 'Sprint burndown. No data.');
    });
  });

  testWidgets('the sparkline draws a chart with no axes or touch', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(SprintBurndownChart(days: _days([10, 7, 3]))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.titlesData.show, isFalse);
    expect(data.lineTouchData.enabled, isFalse);
    expect(data.gridData.show, isFalse);
    // Ideal dashed, actual solid (DESIGN.md §3: never color alone).
    expect(data.lineBarsData.first.dashArray, isNotNull);
    expect(data.lineBarsData.last.dashArray, isNull);
  });

  testWidgets('the full chart adds axes, touch and a legend', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SprintBurndownChart(days: _days([10, 7, 3]), mode: BurndownMode.full),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.titlesData.show, isTrue);
    expect(data.lineTouchData.enabled, isTrue);

    await tester.pumpWidget(_wrap(const BurndownLegend()));
    await tester.pumpAndSettle();
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('Ideal'), findsOneWidget);
  });

  testWidgets('non-working days are banded', (tester) async {
    // 2026-09-12 and 13 are the Saturday and Sunday of this run.
    await tester.pumpWidget(
      _wrap(
        SprintBurndownChart(
          days: _days([10, 9, 8, 8, 8, 6, 4]),
          mode: BurndownMode.full,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.rangeAnnotations.verticalRangeAnnotations, hasLength(2));
  });

  testWidgets('empty and all-null data draw nothing and do not throw', (
    tester,
  ) async {
    for (final days in [
      <BurndownDay>[],
      _days([5]),
      _days([0, 0, 0]),
    ]) {
      await tester.pumpWidget(
        _wrap(SprintBurndownChart(days: days, mode: BurndownMode.full)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the chart carries a semantics label, the chart itself none', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(SprintBurndownChart(days: _days([10, 7, 3]))),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^Sprint burndown\.')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('draws in dark mode too', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SprintBurndownChart(days: _days([10, 7, 3])),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData.last.color, BoardhopColors.dark.burndownActual);
  });
}
