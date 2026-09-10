import 'package:boardhop/core/util/format.dart';
import 'package:boardhop/data/models/board.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/board_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkItem', () {
    final json = <String, dynamic>{
      'id': 15503,
      'rev': 7,
      'url': 'https://dev.azure.com/o/_apis/wit/workItems/15503',
      'fields': {
        'System.WorkItemType': 'Task',
        'System.Title': 'w01 HTML description',
        'System.State': 'New',
        'System.AssignedTo': {
          'displayName': 'Kelly Kamm',
          'uniqueName': 'kelly@example.test',
          'id': 'abc',
        },
        'System.ChangedDate': '2026-09-10T12:00:00Z',
        'System.Tags': 'spike; mobile',
        'System.Description': '# hi',
        'Microsoft.VSTS.Common.Priority': 2,
      },
      'multilineFieldsFormat': {'System.Description': 'Markdown'},
    };

    test('parses fields, identity, tags, format', () {
      final w = WorkItem.fromJson(json);
      expect(w.id, 15503);
      expect(w.rev, 7);
      expect(w.type, 'Task');
      expect(w.assignedTo?.displayName, 'Kelly Kamm');
      expect(w.assignedTo?.initialsLabel, 'KK');
      expect(w.tags, ['spike', 'mobile']);
      expect(w.priority, 2);
      expect(w.formatOf('System.Description'), 'markdown');
      expect(w.formatOf('Microsoft.VSTS.TCM.ReproSteps'), 'html');
      expect(w.changedDate?.toUtc().hour, 12);
    });

    test('round-trips through toJson', () {
      final w = WorkItem.fromJson(json);
      final again = WorkItem.fromJson(w.toJson());
      expect(again, w);
      expect(again.multilineFieldsFormat, w.multilineFieldsFormat);
    });

    test('identity from the legacy string form', () {
      final id = IdentityRef.fromField('Kelly Kamm <kelly@example.test>');
      expect(id?.displayName, 'Kelly Kamm');
      expect(id?.uniqueName, 'kelly@example.test');
      expect(IdentityRef.fromField(null), isNull);
    });

    test('type icons and colors', () {
      final t = WorkItemType.fromJson({
        'name': 'Bug',
        'referenceName': 'Microsoft.VSTS.WorkItemTypes.Bug',
        'color': 'CC293D',
        'icon': {'id': 'icon_insect'},
        'states': [
          {'name': 'New', 'color': 'b2b2b2', 'category': 'Proposed'},
        ],
      });
      expect(t.icon, Icons.bug_report_outlined);
      expect(parseHexColor(t.color), const Color(0xFFCC293D));
      expect(t.stateNamed('New')?.category, 'Proposed');
      expect(WorkItemType.iconFor('nope'), Icons.circle_outlined);
    });
  });

  group('Board', () {
    final board = Board.fromJson({
      'id': 'b1',
      'name': 'Stories',
      'canEdit': true,
      'columns': [
        {
          'id': 'c1',
          'name': 'New',
          'columnType': 'incoming',
          'stateMappings': {'User Story': 'New', 'Bug': 'New'},
        },
        {
          'id': 'c2',
          'name': 'Active',
          'columnType': 'inProgress',
          'itemLimit': 5,
          'isSplit': true,
          'stateMappings': {'User Story': 'Active', 'Bug': 'Active'},
        },
        {
          'id': 'c3',
          'name': 'Closed',
          'columnType': 'outgoing',
          'stateMappings': {'User Story': 'Closed', 'Bug': 'Closed'},
        },
      ],
      'rows': [
        {'id': null, 'name': null},
      ],
      'allowedMappings': {
        'Incoming': {
          'User Story': ['New'],
          'Bug': ['New'],
        },
      },
      'fields': {
        'columnField': {'referenceName': 'WEF_X_Kanban.Column'},
        'rowField': {'referenceName': 'WEF_X_Kanban.Lane'},
        'doneField': {'referenceName': 'WEF_X_Kanban.Column.Done'},
      },
    });

    WorkItem item(int id, String type, String state, {String? column}) =>
        WorkItem(
          id: id,
          rev: 1,
          fields: {
            'System.WorkItemType': type,
            'System.State': state,
            'WEF_X_Kanban.Column': ?column,
          },
        );

    test('parses columns, fields and types', () {
      expect(board.columns.map((c) => c.name), ['New', 'Active', 'Closed']);
      expect(board.columns[1].itemLimit, 5);
      expect(board.columns[1].isSplit, isTrue);
      expect(board.fields.columnField, 'WEF_X_Kanban.Column');
      expect(board.workItemTypes, {'User Story', 'Bug'});
    });

    test('distributes by WEF column, then by state, then first column', () {
      final cards = BoardRepository.distribute(board, [
        item(1, 'Bug', 'Active', column: 'Active'),
        item(2, 'Bug', 'Closed'),
        item(3, 'User Story', 'Weird'),
        item(4, 'Bug', 'New', column: 'Gone'),
      ]);
      expect(cards[0].map((c) => c.id), [3, 4]);
      expect(cards[1].map((c) => c.id), [1]);
      expect(cards[2].map((c) => c.id), [2]);
    });

    test('move ops write column, mapped state and Done only when split', () {
      final ops = BoardRepository.moveOps(
        board,
        item(1, 'Bug', 'New', column: 'New'),
        board.columns[1],
      );
      expect(ops, [
        {'op': 'add', 'path': '/fields/WEF_X_Kanban.Column', 'value': 'Active'},
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
        {'op': 'add', 'path': '/fields/WEF_X_Kanban.Column.Done', 'value': false},
      ]);
      final toClosed = BoardRepository.moveOps(
        board,
        item(1, 'Bug', 'Active'),
        board.columns[2],
      );
      expect(toClosed.length, 2);
      expect(toClosed.any((o) => o['path'].toString().endsWith('.Done')), isFalse);
    });

    test('cards WIQL uses the team areas and escapes quotes', () {
      final wiql = BoardRepository.cardsWiql(
        board,
        const TeamFieldValues(
          field: 'System.AreaPath',
          defaultValue: r'P\Team',
          values: [
            (value: r'P\Team', includeChildren: true),
            (value: r"P\O'Brien", includeChildren: false),
          ],
        ),
        orderBy: '[System.ChangedDate] DESC',
      );
      expect(wiql, contains("[System.WorkItemType] IN ('User Story', 'Bug')"));
      expect(wiql, contains(r"[System.AreaPath] UNDER 'P\Team'"));
      expect(wiql, contains(r"[System.AreaPath] = 'P\O''Brien'"));
      expect(wiql, endsWith('ORDER BY [System.ChangedDate] DESC'));
    });
  });

  group('format helpers', () {
    test('relativeTime', () {
      final now = DateTime(2026, 9, 10, 12);
      expect(relativeTime(now.subtract(const Duration(seconds: 5)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 3)), now: now), '3m');
      expect(relativeTime(now.subtract(const Duration(hours: 5)), now: now), '5h');
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d');
      expect(relativeTime(DateTime(2026, 9, 1), now: now), 'Sep 1');
      expect(relativeTime(DateTime(2025, 9, 1), now: now), 'Sep 1, 2025');
    });

    test('initials and path leaf', () {
      expect(initials('Kelly Kamm'), 'KK');
      expect(initials('kelly'), 'K');
      expect(initials(''), '?');
      expect(pathLeaf(r'CloudCover 2.0\Sprint 12'), 'Sprint 12');
      expect(pathLeaf('Root'), 'Root');
    });
  });
}
