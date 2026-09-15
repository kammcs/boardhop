import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/sprints/widgets/sprint_format.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/features/sprints/widgets/story_chip_strip.dart';
import 'package:boardhop/features/work_items/widgets/work_item_visuals.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkItem _item(int id, String type, String title, String state) => WorkItem(
  id: id,
  rev: 1,
  fields: {
    'System.WorkItemType': type,
    'System.Title': title,
    'System.State': state,
  },
);

final _story = _item(
  15503,
  'User Story',
  'Sign in with Entra on a shared device and stay signed in',
  'Active',
);
final _task = _item(15540, 'Task', 'Rotate the keystore hash', 'To Do');

List<SprintRow> _rows({bool unparented = true}) => [
  SprintRow(tasks: unparented ? [_task] : const []),
  SprintRow(parent: _story, tasks: [_task], remaining: 6),
];

void main() {
  Widget wrap(
    List<SprintRow> rows, {
    String? selected,
    required ValueChanged<String?> onSelected,
    TextScaler scaler = TextScaler.noScaling,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Scaffold(
          body: StoryChipStrip(
            rows: rows,
            visuals: const WorkItemVisuals({}),
            selected: selected,
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  );

  testWidgets('All, Unparented first, then the stories', (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(_rows(), onSelected: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Unparented'), findsOneWidget);
    expect(find.text('#15503 Sign in with Entra on…'), findsOneWidget);
    expect(find.text('Stories…'), findsOneWidget);
  });

  testWidgets('an empty Unparented row is not offered', (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(_rows(unparented: false), onSelected: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('Unparented'), findsNothing);
  });

  testWidgets('selecting a chip reports the row key', (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String?>[];
    await tester.pumpWidget(wrap(_rows(), onSelected: picked.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unparented'));
    await tester.pumpAndSettle();
    expect(picked, [kUnparentedRowKey]);

    await tester.tap(find.text('#15503 Sign in with Entra on…'));
    await tester.pumpAndSettle();
    expect(picked.last, '15503');
  });

  testWidgets('at xxxL the chips carry ids only', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(_rows(), onSelected: (_) {}, scaler: const TextScaler.linear(3)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('#15503'), findsOneWidget);
    expect(find.textContaining('Sign in with Entra'), findsNothing);
  });

  testWidgets('the Stories… sheet lists title, state, count and rollup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String?>[];
    await tester.pumpWidget(wrap(_rows(), onSelected: picked.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stories…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sign in with Entra on a shared device and stay signed in'),
      findsOneWidget,
    );
    expect(find.text('Active · 1 task · 6 h remaining'), findsOneWidget);

    await tester.tap(
      find.text('Sign in with Entra on a shared device and stay signed in'),
    );
    await tester.pumpAndSettle();
    expect(picked, ['15503']);
  });

  testWidgets('the sheet can go back to All', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String?>[];
    await tester.pumpWidget(
      wrap(_rows(), selected: '15503', onSelected: picked.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stories…'));
    await tester.pumpAndSettle();
    // The chip strip also has an All chip; the sheet's is the TextButton.
    await tester.tap(
      find.descendant(of: find.byType(TextButton), matching: find.text('All')),
    );
    await tester.pumpAndSettle();
    expect(picked, [null]);
  });
}
