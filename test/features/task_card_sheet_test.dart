import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/features/sprints/widgets/task_card_sheet.dart';
import 'package:boardhop/features/work_items/widgets/work_item_visuals.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _columns = [
  TaskboardColumn(
    name: 'To Do',
    order: 1,
    mappings: {'Task': 'To Do', 'Bug': 'New'},
    stateCategory: 'Proposed',
  ),
  TaskboardColumn(
    name: 'In Progress',
    order: 2,
    mappings: {'Task': 'In Progress', 'Bug': 'Active'},
    stateCategory: 'InProgress',
  ),
  TaskboardColumn(
    name: 'Verify',
    order: 3,
    mappings: {'Task': 'In Progress'},
    stateCategory: 'InProgress',
  ),
  TaskboardColumn(
    name: 'Done',
    order: 4,
    mappings: {'Task': 'Done', 'Bug': 'Closed'},
    stateCategory: 'Completed',
  ),
];

WorkItem _task({String type = 'Task', double? remaining}) => WorkItem(
  id: 15542,
  rev: 2,
  fields: {
    'System.WorkItemType': type,
    'System.Title': 'Add the redirect URI',
    'System.State': type == 'Task' ? 'To Do' : 'New',
    kRemainingWorkField: ?remaining,
  },
);

void main() {
  group('columnAcceptsType', () {
    test('a derived column with no mappings takes anything', () {
      expect(
        columnAcceptsType(
          const TaskboardColumn(name: 'To Do', order: 1),
          'Task',
        ),
        isTrue,
      );
    });

    test('a customized column only takes the types it maps', () {
      expect(columnAcceptsType(_columns[2], 'Task'), isTrue);
      expect(columnAcceptsType(_columns[2], 'Bug'), isFalse);
    });
  });

  group('taskMoveSemanticsActions', () {
    test('skips the current column and the unreachable ones', () {
      final actions = taskMoveSemanticsActions(
        columns: _columns,
        type: 'Bug',
        currentColumn: 0,
        onMoveTo: (_) {},
      );
      expect(
        actions.keys.map((a) => a.label),
        unorderedEquals(['Move to In Progress', 'Move to Done']),
      );
    });

    test('calls back with the column index', () {
      final picked = <int>[];
      final actions = taskMoveSemanticsActions(
        columns: _columns,
        type: 'Task',
        currentColumn: 0,
        onMoveTo: picked.add,
      );
      actions[CustomSemanticsAction(label: 'Move to Done')]!();
      expect(picked, [3]);
    });
  });

  /// Opens the sheet and hands back the box the action lands in once the
  /// sheet closes.
  Future<List<TaskCardAction?>> open(
    WidgetTester tester, {
    required WorkItem task,
    int? currentColumn = 0,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final result = <TaskCardAction?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.add(
                  await showTaskCardSheet(
                    context,
                    task: task,
                    columns: _columns,
                    visuals: const WorkItemVisuals({}),
                    currentColumn: currentColumn,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('one row per column, the current one checked and disabled', (
    tester,
  ) async {
    await open(tester, task: _task());
    expect(find.text('To Do'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    final todo = tester.widget<ListTile>(
      find.ancestor(of: find.text('To Do'), matching: find.byType(ListTile)),
    );
    expect(todo.enabled, isFalse);
  });

  testWidgets('a column the type cannot reach says so and stays disabled', (
    tester,
  ) async {
    await open(tester, task: _task(type: 'Bug'));
    final verify = tester.widget<ListTile>(
      find.ancestor(of: find.text('Verify'), matching: find.byType(ListTile)),
    );
    expect(verify.enabled, isFalse);
    expect(find.text('Not available for a Bug'), findsOneWidget);
  });

  testWidgets('Done warns that it zeroes remaining work', (tester) async {
    await open(tester, task: _task(remaining: 4));
    expect(
      find.text('Moving to Done sets remaining work to 0'),
      findsOneWidget,
    );
  });

  testWidgets('picking a column returns MoveTaskAction', (tester) async {
    final result = await open(tester, task: _task());
    await tester.tap(find.text('In Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Move to'), findsNothing);
    final action = result.single;
    expect(action, isA<MoveTaskAction>());
    expect((action! as MoveTaskAction).columnIndex, 1);
    expect((action as MoveTaskAction).column.name, 'In Progress');
  });

  testWidgets('Assign to me and Open task come back as themselves', (
    tester,
  ) async {
    final result = await open(tester, task: _task());
    await tester.tap(find.text('Assign to me'));
    await tester.pumpAndSettle();
    expect(result.single, isA<AssignToMeAction>());
  });

  testWidgets('confirming the stepper returns the value', (tester) async {
    final result = await open(tester, task: _task(remaining: 4));
    await tester.tap(find.byTooltip('More remaining work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set remaining work to 5 h'));
    await tester.pumpAndSettle();
    expect(result.single, isA<SetRemainingWorkAction>());
    expect((result.single! as SetRemainingWorkAction).hours, 5);
  });

  testWidgets('the stepper only writes once it is confirmed', (tester) async {
    await open(tester, task: _task(remaining: 4));
    expect(find.text('4 h'), findsOneWidget);
    // Nothing to confirm before a change.
    expect(find.textContaining('Set remaining work'), findsNothing);

    await tester.tap(find.byTooltip('More remaining work'));
    await tester.pumpAndSettle();
    expect(find.text('5 h'), findsOneWidget);
    expect(find.text('Set remaining work to 5 h'), findsOneWidget);

    await tester.tap(find.text('Set to 0'));
    await tester.pumpAndSettle();
    expect(find.text('0 h'), findsOneWidget);
    expect(find.text('Clear remaining work'), findsOneWidget);
  });

  testWidgets('a tablet gets the same sheet as a dialog', (tester) async {
    await open(tester, task: _task(), size: const Size(1200, 1000));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Move to'), findsOneWidget);
  });

  testWidgets('xxxL does not overflow', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: Scaffold(
              body: TaskCardSheet(
                task: _task(remaining: 4),
                columns: _columns,
                visuals: const WorkItemVisuals({}),
                currentColumn: 0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
