import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/sprints/widgets/sprint_backlog_tab.dart';
import 'package:boardhop/features/work_items/widgets/work_item_visuals.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Backlog tab on its own: the tab that has to work on CloudCover 2.0,
/// where the sprint holds 143 requirement rows and 5 task-type items
/// (research/18 §5.3), so it is a list and never a board.
void main() {
  WorkItem story(int id, String title, {String state = 'Active'}) =>
      WorkItem.fromJson({
        'id': id,
        'rev': 2,
        'fields': {
          'System.Id': id,
          'System.WorkItemType': 'User Story',
          'System.Title': title,
          'System.State': state,
        },
      });

  WorkItem task(int id, String title, {double? remaining}) =>
      WorkItem.fromJson({
        'id': id,
        'rev': 1,
        'fields': {
          'System.Id': id,
          'System.WorkItemType': 'Task',
          'System.Title': title,
          'System.State': 'To Do',
          'Microsoft.VSTS.Scheduling.RemainingWork': ?remaining,
        },
      });

  final rows = [
    SprintRow(
      parent: story(15503, 'First by rank'),
      tasks: [task(15550, 'One'), task(15551, 'Two')],
      remaining: 7,
      done: 1,
    ),
    SprintRow(parent: story(15510, 'Second by rank')),
  ];

  Widget harness({
    List<SprintRow>? withRows,
    SprintCapacity? capacity,
    List<WorkItem>? opened,
    List<(SprintRowAction, int)>? actions,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Scaffold(
      body: SprintBacklogTab(
        rows: withRows ?? rows,
        visuals: const WorkItemVisuals({}),
        capacity: capacity,
        onOpen: (item) => opened?.add(item),
        onRowAction: (action, row, item) => actions?.add((action, item.id)),
      ),
    ),
  );

  testWidgets('a row shows its state, id, task count and rollup', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('First by rank'), findsOneWidget);
    expect(find.text('User Story 15503'), findsOneWidget);
    expect(find.text('2 tasks · 1 done'), findsOneWidget);
    expect(find.text('7 h remaining'), findsOneWidget);
    // The rollup is absent, not "0 h", when no task carries the field —
    // which is every team probed (spike s54).
    expect(find.text('No tasks'), findsOneWidget);
  });

  testWidgets('the service\'s rank order is kept', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('First by rank'));
    final second = tester.getTopLeft(find.text('Second by rank'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('tapping a row opens its work item', (tester) async {
    final opened = <WorkItem>[];
    await tester.pumpWidget(harness(opened: opened));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First by rank'));
    await tester.pumpAndSettle();

    expect(opened.single.id, 15503);
  });

  testWidgets('the overflow offers both row writes (S3)', (tester) async {
    final actions = <(SprintRowAction, int)>[];
    await tester.pumpWidget(harness(actions: actions));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More for 15503'));
    await tester.pumpAndSettle();

    expect(find.text('Move to another sprint'), findsOneWidget);
    // A story with no tasks is reached from here, since the taskboard only
    // draws rows that have some.
    expect(find.text('Add task'), findsOneWidget);
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();

    expect(actions.single, (SprintRowAction.addTask, 15503));
  });

  testWidgets('unparented tasks are their own rows, with the same overflow', (
    tester,
  ) async {
    final actions = <(SprintRowAction, int)>[];
    await tester.pumpWidget(
      harness(
        withRows: [
          SprintRow(tasks: [task(15599, 'An orphan')]),
          ...rows,
        ],
        actions: actions,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unparented tasks'), findsOneWidget);
    expect(find.text('An orphan'), findsOneWidget);
    await tester.tap(find.byTooltip('More for 15599'));
    await tester.pumpAndSettle();
    // No "Add task": a task is not a parent.
    expect(find.text('Add task'), findsNothing);
    await tester.tap(find.text('Move to another sprint'));
    await tester.pumpAndSettle();

    expect(actions.single, (SprintRowAction.moveToSprint, 15599));
  });

  group('the capacity strip (S7)', () {
    SprintCapacity filled() => SprintCapacity.fromJson({
      'teamMembers': [
        {
          'teamMember': {'displayName': 'Kelly Kamm', 'id': 'k'},
          'activities': [
            {'name': 'Development', 'capacityPerDay': 6},
          ],
          'daysOff': [
            {'start': '2026-09-10T00:00:00Z', 'end': '2026-09-11T00:00:00Z'},
          ],
        },
      ],
      'workingDays': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
    });

    testWidgets('is absent when the team filled nothing in', (tester) async {
      await tester.pumpWidget(harness(capacity: const SprintCapacity()));
      await tester.pumpAndSettle();

      expect(find.text('Capacity'), findsNothing);
    });

    testWidgets('shows the total, the people and their days off', (
      tester,
    ) async {
      await tester.pumpWidget(harness(capacity: filled()));
      await tester.pumpAndSettle();

      expect(find.text('Capacity'), findsOneWidget);
      expect(find.text('6 h a day across 1 person'), findsOneWidget);
      expect(find.text('Kelly Kamm'), findsOneWidget);
      expect(find.text('6 h/day · 2 days off'), findsOneWidget);
    });
  });

  testWidgets('an empty sprint says so in one sentence', (tester) async {
    await tester.pumpWidget(harness(withRows: const []));
    await tester.pumpAndSettle();

    expect(find.text('Nothing is in this sprint yet.'), findsOneWidget);
  });
}
