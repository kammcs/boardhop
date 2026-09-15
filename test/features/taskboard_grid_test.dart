import 'package:boardhop/features/boards/widgets/kanban_board.dart';
import 'package:boardhop/features/diagnostics/sprint_probe/sprint_probe_data.dart';
import 'package:boardhop/features/diagnostics/sprint_probe/sprint_probe_page.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/features/sprints/widgets/taskboard_grid.dart';
import 'package:boardhop/features/work_items/widgets/work_item_visuals.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A move as the grid reported it.
typedef _Move = (int fromRow, int fromColumn, int toRow, int toColumn, int at);

void main() {
  late SprintProbeState state;
  late List<_Move> moves;

  setUp(() {
    state = SprintProbeState(SprintProbeData.generate());
    moves = [];
  });

  Widget grid({
    TextScaler scaler = TextScaler.noScaling,
    ValueChanged<SprintRow>? onAddTask,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TaskboardGrid(
              columns: state.data.columns,
              rows: state.rows,
              columnOf: state.columnOf,
              visuals: const WorkItemVisuals({}),
              cardBuilder: (context, card, dragging) => WorkItemCard(
                item: card,
                visuals: const WorkItemVisuals({}),
                dragging: dragging,
              ),
              onAddTask: onAddTask,
              onMove: (card, fromRow, fromColumn, toRow, toColumn, at) {
                moves.add((fromRow, fromColumn, toRow, toColumn, at));
                setState(() => state.move(card, toRow, toColumn, at));
              },
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('draws sticky column headers, row headers and cells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    // One header per column. The names are also card states, so the
    // header widget is what is counted.
    expect(
      find.byType(KanbanColumnHeader),
      findsNWidgets(state.data.columns.length),
    );
    expect(find.text('Verify'), findsOneWidget);
    // Every row header, Unparented pinned first.
    expect(find.text('Unparented'), findsOneWidget);
    expect(find.text('Sign in with Entra on a shared device'), findsOneWidget);
    expect(find.text('Sign out everywhere'), findsOneWidget);
    // A row with no tasks says so rather than vanishing.
    expect(find.text('No tasks'), findsOneWidget);
    // Cards are in their cells.
    expect(find.text('Task 15542'), findsOneWidget);
    // The Unparented row explains itself.
    expect(
      find.text('These tasks have no parent in this sprint.'),
      findsOneWidget,
    );
  });

  testWidgets('a collapsed row keeps its per-column counts', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    expect(find.text('Task 15542'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse row').at(1));
    await tester.pumpAndSettle();

    // The story's cards are gone, the counts took their place: two To Do,
    // one In Progress in the third column's terms, one Done.
    expect(find.text('Task 15542'), findsNothing);
    expect(find.text('1 · 2 · 0 · 1'), findsOneWidget);
    expect(find.byTooltip('Expand row'), findsOneWidget);
  });

  testWidgets('the row header + adds a task to that row', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final added = <SprintRow>[];
    await tester.pumpWidget(grid(onAddTask: added.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add task').at(1));
    await tester.pumpAndSettle();
    expect(added.single.parent?.id, 15503);
  });

  testWidgets('long-press drag moves a card across cells', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    // Unparented / To Do → the story row's In Progress cell.
    final source = find.text('Task 15540');
    final target = find.text('Task 15543');
    expect(source, findsOneWidget);
    expect(target, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moves, hasLength(1));
    final (fromRow, fromColumn, toRow, toColumn, _) = moves.single;
    expect(fromRow, 0);
    expect(fromColumn, 0);
    expect(toRow, 1);
    expect(toColumn, 1);
    // The probe applied the column's state mapping for a Task.
    final moved = state.rows[0].tasks.firstWhere((t) => t.id == 15540);
    expect(moved.state, 'In Progress');
  });

  testWidgets('survives xxxL text without overflowing', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(grid(scaler: const TextScaler.linear(3)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Unparented'), findsOneWidget);
  });
}
