import 'package:boardhop/features/sprints/widgets/sprint_burndown_chart.dart';
import 'package:boardhop/features/sprints/widgets/sprint_format.dart';
import 'package:boardhop/features/sprints/widgets/sprint_header.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<BurndownDay> _days(List<int> remaining) => [
  for (var i = 0; i < remaining.length; i++)
    BurndownDay(
      date: DateTime.utc(2026, 9, 7).add(Duration(days: i)),
      remaining: remaining[i],
    ),
];

void main() {
  group('sprintVerdict', () {
    test('no data at all', () {
      expect(sprintVerdict(const [], null, const []), 'No burndown data');
      expect(sprintVerdict(_days([10, 5]), null, const []), 'No burndown data');
    });

    test('an ended sprint says how long ago, not how it burned down', () {
      expect(
        sprintVerdict(
          _days([10, 5]),
          5,
          burndownIdealLine(_days([10, 5])),
          isEnded: true,
          finish: DateTime.utc(2026, 9, 12),
          now: DateTime.utc(2026, 9, 15),
        ),
        'Ended 3 days ago',
      );
    });

    test('an ended sprint with no dates has no day count', () {
      expect(
        sprintVerdict(_days([10, 5]), 5, const [10, 0], isEnded: true),
        'Ended',
      );
    });

    // Analytics has three days of a five-day sprint: the ideal line runs to
    // the end, the snapshots stop at today.
    const fiveDayIdeal = [10.0, 7.5, 5.0, 2.5, 0.0];

    test('ahead of the ideal line', () {
      // Day 3 of 5: ideal 5, actual 1, so 4 units of head start spread over
      // the two days that are left.
      expect(
        sprintVerdict(_days([10, 8, 1]), null, fiveDayIdeal),
        'About 2 items/day ahead of the ideal line',
      );
    });

    test('behind the ideal line, in the sprint unit', () {
      expect(
        sprintVerdict(_days([10, 8, 9]), null, fiveDayIdeal, unit: 'h'),
        'About 2 h/day behind the ideal line',
      );
    });

    test('an explicit daysLeft beats the length of the ideal line', () {
      expect(
        sprintVerdict(_days([10, 8, 9]), null, fiveDayIdeal, daysLeft: 4),
        'About 1 items/day behind the ideal line',
      );
    });

    test('on the line', () {
      final days = _days([10, 5]);
      expect(
        sprintVerdict(days, 0, burndownIdealLine(days)),
        'On the ideal line',
      );
    });

    test('on the last day the gap is stated, not turned into a rate', () {
      // Day 3 of 3: the ideal is 0 and 6 are left, and there is no day to
      // spread that over.
      final days = _days([10, 8, 6]);
      expect(
        sprintVerdict(days, null, burndownIdealLine(days)),
        '6 items behind the ideal line',
      );
    });

    test('a fresher remaining figure beats the last snapshot', () {
      final days = _days([10, 8, 6]);
      expect(
        sprintVerdict(days, 6, fiveDayIdeal),
        sprintVerdict(days, null, fiveDayIdeal),
      );
      expect(
        sprintVerdict(days, 2, fiveDayIdeal),
        'About 1.5 items/day ahead of the ideal line',
      );
    });
  });

  group('sprint dates', () {
    test('a range inside one month, across months, across years', () {
      expect(
        sprintDateRange(DateTime.utc(2026, 11, 3), DateTime.utc(2026, 11, 14)),
        '3–14 Nov',
      );
      expect(
        sprintDateRange(DateTime.utc(2026, 10, 28), DateTime.utc(2026, 11, 8)),
        '28 Oct – 8 Nov',
      );
      expect(
        sprintDateRange(DateTime.utc(2025, 12, 29), DateTime.utc(2026, 1, 9)),
        '29 Dec 2025 – 9 Jan 2026',
      );
    });

    test('an undated sprint is a real state, not a blank', () {
      expect(sprintDateRange(null, null), 'Dates not set');
    });

    test('days left and ended', () {
      expect(
        sprintDaysLeft(
          DateTime.utc(2026, 9, 18),
          now: DateTime.utc(2026, 9, 15),
        ),
        3,
      );
      expect(
        sprintEndedLabel(
          DateTime.utc(2026, 9, 14),
          now: DateTime.utc(2026, 9, 15),
        ),
        'Ended 1 day ago',
      );
      expect(sprintEndedLabel(null), 'Ended');
    });
  });

  group('formatRemaining', () {
    test('whole hours, halves, and nothing at all', () {
      expect(formatRemaining(12), '12 h');
      expect(formatRemaining(1.5), '1.5 h');
      expect(formatRemaining(null), '');
      expect(formatRemaining(0), '');
    });
  });

  Widget wrap(SprintHeaderData data, {TextScaler? scaler}) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: scaler ?? TextScaler.noScaling),
        child: Scaffold(body: SprintHeader(data: data)),
      ),
    ),
  );

  testWidgets('tiles, sparkline, verdict and dates', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        SprintHeaderData(
          remaining: 30,
          done: 4,
          total: 12,
          scopeChange: 6,
          days: _days([30, 24, 20]),
          start: DateTime.utc(2026, 9, 7),
          finish: DateTime.utc(2026, 9, 18),
          now: DateTime.utc(2026, 9, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('30 items'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('+6'), findsOneWidget);
    expect(find.text('7–18 Sep · 3 days left'), findsOneWidget);
    expect(find.byType(SprintBurndownChart), findsOneWidget);
  });

  testWidgets('hours on the tile, items in the verdict and the sparkline', (
    tester,
  ) async {
    // One task with Remaining Work flips the rollup to hours. The burndown
    // is still a count of work items, so the sentence must stay in items
    // and the sparkline must stay on screen — dropping the series there
    // made a sprint with four days of history read "No burndown data"
    // (iPhone check, P-D).
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        SprintHeaderData(
          remaining: 2,
          done: 0,
          total: 14,
          days: _days([17, 17, 17, 17]),
          start: DateTime.utc(2026, 9, 8),
          finish: DateTime.utc(2026, 9, 21),
          now: DateTime.utc(2026, 9, 15),
          unit: 'h',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 h'), findsOneWidget);
    expect(find.text('No burndown data'), findsNothing);
    expect(
      find.textContaining('items/day behind the ideal line'),
      findsOneWidget,
    );
    expect(find.byType(SprintBurndownChart), findsOneWidget);
  });

  testWidgets('an empty sprint shows dashes and no chart', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const SprintHeaderData()));
    await tester.pumpAndSettle();
    expect(find.text('No burndown data'), findsOneWidget);
    expect(find.text('Dates not set'), findsOneWidget);
    expect(find.byType(SprintBurndownChart), findsNothing);
  });

  testWidgets('xxxL drops the sparkline and keeps the sentence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        SprintHeaderData(
          remaining: 30,
          done: 4,
          total: 12,
          days: _days([30, 24, 20]),
          now: DateTime.utc(2026, 9, 15),
        ),
        scaler: const TextScaler.linear(3),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SprintBurndownChart), findsNothing);
    expect(find.textContaining('the ideal line'), findsOneWidget);
  });
}
