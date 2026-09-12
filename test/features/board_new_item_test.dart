import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/board.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/board_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/boards/widgets/kanban_board.dart';
import 'package:boardhop/features/boards/widgets/new_card_row.dart';
import 'package:boardhop/features/work_items/form/work_item_form_page.dart';
import 'package:boardhop/features/work_items/form/work_item_form_state.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _laneField = 'WEF_6f9b8d1c_Kanban.Lane';

/// The scratch board: New, Active split into Doing/Done, Closed, plus the
/// Expedite swimlane spike w05 configured.
Board _board() => Board.fromJson({
  'id': 'board-1',
  'name': 'Stories',
  'columns': [
    {
      'id': 'c0',
      'name': 'New',
      'columnType': 'incoming',
      'stateMappings': {'User Story': 'New', 'Bug': 'New'},
    },
    {
      'id': 'c1',
      'name': 'Active',
      'columnType': 'inProgress',
      'isSplit': true,
      'itemLimit': 5,
      'stateMappings': {'User Story': 'Active', 'Bug': 'Active'},
    },
    {
      'id': 'c2',
      'name': 'Closed',
      'columnType': 'outgoing',
      'stateMappings': {'User Story': 'Closed', 'Bug': 'Closed'},
    },
  ],
  'rows': [
    {'id': 'r0', 'name': null},
    {'id': 'r1', 'name': 'Expedite'},
  ],
  'fields': {
    'columnField': {'referenceName': 'WEF_6f9b8d1c_Kanban.Column'},
    'rowField': {'referenceName': _laneField},
    'doneField': {'referenceName': 'WEF_6f9b8d1c_Kanban.Column.Done'},
  },
});

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<Map<String, dynamic>> _values(Map<String, dynamic> json) => [
  for (final v in (json['value'] as List?) ?? const [])
    if (v is Map) v.cast<String, dynamic>(),
];

FormSpec _bugSpec() {
  final orgFields = {
    for (final f in _values(_fixture('org_fields.json')))
      (f['referenceName'] as String): FieldSpec.fromOrgField(f),
  };
  return WorkItemFormRepository.buildSpec(
    typeJson: _fixture('scratch_bug_type.json'),
    typeFields: _values(_fixture('scratch_bug_fields.json')),
    orgFields: orgFields,
  );
}

void main() {
  group("a board column's +", () {
    test('takes the state the column maps for the type', () {
      final board = _board();
      final params = BoardRepository.newCardParams(
        board,
        board.columns[1],
        'Bug',
      );
      expect(params.state, 'Active');
      // No lane is on screen: the row field is not pre-filled.
      expect(params.laneField, isNull);
      expect(params.lane, isNull);
    });

    test('takes the lane on screen through the board row field', () {
      final board = _board();
      final params = BoardRepository.newCardParams(
        board,
        board.columns[1],
        'User Story',
        lane: 'Expedite',
      );
      expect(params.state, 'Active');
      expect(params.laneField, _laneField);
      expect(params.lane, 'Expedite');
    });

    test('the default lane carries no value', () {
      final board = _board();
      final params = BoardRepository.newCardParams(
        board,
        board.columns[0],
        'Bug',
        lane: '',
      );
      expect(params.state, 'New');
      expect(params.laneField, isNull);
      expect(params.lane, isNull);
    });

    test('a column that does not map the type has no state', () {
      final board = _board();
      final params = BoardRepository.newCardParams(
        board,
        board.columns[0],
        'Task',
      );
      expect(params.state, isNull);
    });

    testWidgets('renders a New item row under the last card of a column', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tapped = -1;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: KanbanBoard<String>(
              columns: const [
                KanbanColumnData<String>(
                  id: 'c0',
                  title: 'New',
                  cards: ['one'],
                ),
              ],
              keyOf: (c) => c,
              cardBuilder: (context, card, dragging) => Text(card),
              onMove: (_, _, _, _, _) {},
              columnFooterBuilder: (context, column) =>
                  NewCardRow(onTap: () => tapped = column),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('New item'), findsOneWidget);
      await tester.tap(find.text('New item'));
      expect(tapped, 0);
    });
  });

  group('create, then move to the column (spike w18)', () {
    test('the create patch never carries State', () {
      final spec = _bugSpec();
      final form = WorkItemFormState(
        spec: spec,
        // The header shows where the card will land, but only the type's
        // initial state is legal on a create.
        initialValues: {
          'System.Title': '[phase4] from the Active column',
          'System.State': 'Active',
        },
      );
      final ops = form.buildOps();
      expect(
        ops.any((op) => op['path'] == '/fields/System.Title'),
        isTrue,
        reason: 'the title still goes in',
      );
      expect(
        ops.any((op) => '${op['path']}'.endsWith('System.State')),
        isFalse,
      );
      expect(
        ops.any((op) => '${op['path']}'.endsWith('System.Reason')),
        isFalse,
      );
      form.dispose();
    });

    test('the follow-up patch carries the state and the lane field', () {
      final created = WorkItem.fromJson({
        'id': 15560,
        'rev': 1,
        'fields': {
          'System.WorkItemType': 'Bug',
          'System.State': 'New',
          'System.Title': '[phase4] from the Active column',
        },
      });
      final ops = boardFollowUpOps(
        created,
        stateName: 'Active',
        laneField: _laneField,
        lane: 'Expedite',
      );
      expect(ops, [
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
        {'op': 'add', 'path': '/fields/$_laneField', 'value': 'Expedite'},
      ]);
      // WorkItemRepository.patch opens every patch with the guard.
      final sent = [
        {'op': 'test', 'path': '/rev', 'value': created.rev},
        ...ops,
      ];
      expect(sent.first, {'op': 'test', 'path': '/rev', 'value': 1});
    });

    test('nothing to do when the server already landed it there', () {
      final created = WorkItem.fromJson({
        'id': 15561,
        'rev': 1,
        'fields': {'System.State': 'New', _laneField: 'Expedite'},
      });
      expect(
        boardFollowUpOps(
          created,
          stateName: 'New',
          laneField: _laneField,
          lane: 'Expedite',
        ),
        isEmpty,
      );
      expect(boardFollowUpOps(created), isEmpty);
    });
  });
}
