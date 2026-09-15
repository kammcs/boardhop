import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/features/sprints/widgets/person_filter_menu.dart';
import 'package:boardhop/features/sprints/widgets/sprint_picker_sheet.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _iterations = [
  TeamIteration(
    id: 'iter-1',
    name: 'Iteration 1',
    path: r'Scratch\Iteration 1',
    timeFrame: 'current',
    startDate: DateTime.utc(2026, 9, 7),
    finishDate: DateTime.utc(2026, 9, 18),
  ),
  const TeamIteration(
    id: 'iter-2',
    name: 'Iteration 2',
    path: r'Scratch\Iteration 2',
    timeFrame: 'future',
  ),
  TeamIteration(
    id: 'iter-0',
    name: 'Iteration 0',
    path: r'Scratch\Iteration 0',
    timeFrame: 'past',
    startDate: DateTime.utc(2026, 8, 24),
    finishDate: DateTime.utc(2026, 9, 4),
  ),
];

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets('groups Current, Future and Past and names the team', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        SprintPickerSheet(
          iterations: _iterations,
          teamName: 'Scratch Team',
          currentIterationId: 'iter-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Future'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Scratch Team'), findsOneWidget);
    expect(find.text('7–18 Sep'), findsOneWidget);
    // An undated sprint is shown, greyed, never hidden (S11).
    expect(find.text('Dates not set'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // One team means no switch.
    expect(find.text('Switch team'), findsNothing);
  });

  testWidgets('picking a sprint returns it', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <SprintPickerResult?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked.add(
                await showSprintPicker(
                  context,
                  iterations: _iterations,
                  teamName: 'Scratch Team',
                  currentIterationId: 'iter-1',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iteration 2'));
    await tester.pumpAndSettle();

    expect(picked.single, isA<SprintIterationPicked>());
    expect((picked.single! as SprintIterationPicked).iteration.id, 'iter-2');
  });

  testWidgets('a second team adds the switch row', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        const SprintPickerSheet(
          iterations: [],
          teamName: 'Scratch Team',
          teams: [
            SprintTeamRef(id: 't1', name: 'Scratch Team'),
            SprintTeamRef(id: 't2', name: 'Relay Team'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Switch team'), findsOneWidget);
    expect(find.text('This team has no sprints.'), findsOneWidget);
  });

  testWidgets('a tablet gets the picker as a dialog', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSprintPicker(
                context,
                iterations: _iterations,
                teamName: 'Scratch Team',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Sprints'), findsOneWidget);
  });

  testWidgets('xxxL does not overflow', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
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
              body: SprintPickerSheet(
                iterations: _iterations,
                teamName: 'Scratch Team',
                currentIterationId: 'iter-1',
                teams: const [
                  SprintTeamRef(id: 't1', name: 'Scratch Team'),
                  SprintTeamRef(id: 't2', name: 'Relay Team'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('PersonFilterMenu', () {
    testWidgets('Everyone, Me and each member with a count', (tester) async {
      String? selected = kMePersonFilter;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                StatefulBuilder(
                  builder: (context, setState) => PersonFilterMenu(
                    people: const [
                      SprintPerson(id: 'p1', displayName: 'Ada Moss', count: 3),
                    ],
                    selected: selected,
                    meCount: 2,
                    onSelected: (value) => setState(() => selected = value),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PersonFilterMenu));
      await tester.pumpAndSettle();
      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Me · 2'), findsOneWidget);
      expect(find.text('Ada Moss · 3'), findsOneWidget);

      await tester.tap(find.text('Everyone'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });
  });
}
