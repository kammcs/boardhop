import 'package:boardhop/core/util/format.dart';
import 'package:boardhop/data/models/board.dart';
import 'package:boardhop/data/avatar_store.dart';
import 'package:boardhop/data/repositories/account_repository.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/board_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
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

    test('transitions come back in the type own state order', () {
      final t = WorkItemType.fromJson({
        'name': 'Bug',
        'referenceName': 'Microsoft.VSTS.WorkItemTypes.Bug',
        'states': [
          {'name': 'New'},
          {'name': 'Active'},
          {'name': 'Resolved'},
          {'name': 'Closed'},
          {'name': 'Removed'},
        ],
        // The map answers in an order of its own (spike w18).
        'transitions': {
          'New': [
            {'to': 'New'},
            {'to': 'Closed'},
            {'to': 'Resolved'},
            {'to': 'Active'},
            {'to': 'Somewhere else'},
          ],
        },
      });

      expect(t.transitionsFrom('New'), const [
        'New',
        'Active',
        'Resolved',
        'Closed',
        // A state the type does not list keeps the order it came in.
        'Somewhere else',
      ]);
      expect(t.transitionsFrom('Closed'), isEmpty);
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

    test('slots split a column into Doing and Done', () {
      expect(board.slots.map((s) => s.id), ['c1', 'c2/doing', 'c2/done', 'c3']);
      expect(board.slots[2].subtitle, 'Done');
      expect(board.hasLanes, isFalse);
    });

    test('distributes by WEF column and Done flag, then state, then first', () {
      final done = WorkItem(
        id: 5,
        rev: 1,
        fields: {
          'System.WorkItemType': 'Bug',
          'System.State': 'Active',
          'WEF_X_Kanban.Column': 'Active',
          'WEF_X_Kanban.Column.Done': true,
        },
      );
      final cards = BoardRepository.distribute(board, [
        item(1, 'Bug', 'Active', column: 'Active'),
        item(2, 'Bug', 'Closed'),
        item(3, 'User Story', 'Weird'),
        item(4, 'Bug', 'New', column: 'Gone'),
        done,
      ]);
      expect(cards[0].map((c) => c.id), [3, 4]);
      expect(cards[1].map((c) => c.id), [1]);
      expect(cards[2].map((c) => c.id), [5]);
      expect(cards[3].map((c) => c.id), [2]);
    });

    test('move ops write column, mapped state and Done only when split', () {
      final ops = BoardRepository.moveOps(
        board,
        item(1, 'Bug', 'New', column: 'New'),
        board.slots[2],
      );
      expect(ops, [
        {'op': 'add', 'path': '/fields/WEF_X_Kanban.Column', 'value': 'Active'},
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
        {
          'op': 'add',
          'path': '/fields/WEF_X_Kanban.Column.Done',
          'value': true,
        },
      ]);
      final toClosed = BoardRepository.moveOps(
        board,
        item(1, 'Bug', 'Active'),
        board.slots[3],
      );
      expect(toClosed.length, 2);
      expect(
        toClosed.any((o) => o['path'].toString().endsWith('.Done')),
        isFalse,
      );
      // Same column, other half: only the Done flag changes.
      final toDone = BoardRepository.moveOps(
        board,
        item(1, 'Bug', 'Active', column: 'Active'),
        board.slots[2],
      );
      expect(toDone, [
        {
          'op': 'add',
          'path': '/fields/WEF_X_Kanban.Column.Done',
          'value': true,
        },
      ]);
    });

    test('reorder block bundles unranked neighbours', () {
      WorkItem w(int id, [double? rank]) => WorkItem(
        id: id,
        rev: 1,
        fields: {'Microsoft.VSTS.Common.StackRank': ?rank},
      );
      const rank = 'Microsoft.VSTS.Common.StackRank';
      // Ranked above and below: only the card itself.
      var b = BoardRepository.reorderBlock([w(1, 1), w(2), w(3, 3)], 1, rank);
      expect(b.ids, [2]);
      expect((b.previousId, b.nextId), (1, 3));
      // Unranked neighbours join the block, bounded by ranked cards.
      b = BoardRepository.reorderBlock(
        [w(1, 1), w(2), w(3), w(4), w(5, 5)],
        2,
        rank,
      );
      expect(b.ids, [2, 3, 4]);
      expect((b.previousId, b.nextId), (1, 5));
      // No ranked cards at all: the whole slot, start to end.
      b = BoardRepository.reorderBlock([w(1), w(2)], 1, rank);
      expect(b.ids, [1, 2]);
      expect((b.previousId, b.nextId), (0, 0));
      // No rank field known: neighbours count as unranked too.
      b = BoardRepository.reorderBlock([w(1, 1), w(2, 2)], 0, null);
      expect(b.ids, [1, 2]);
    });

    test('lane of a card comes from the row field', () {
      expect(BoardRepository.laneOf(board, item(1, 'Bug', 'New')), '');
      final laned = WorkItem(
        id: 9,
        rev: 1,
        fields: {'WEF_X_Kanban.Lane': 'Expedite'},
      );
      expect(BoardRepository.laneOf(board, laned), 'Expedite');
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

  group('saved queries', () {
    test('tree leaves and folders', () {
      final tree = [
        SavedQuery.fromJson({
          'id': 'root',
          'name': 'Shared Queries',
          'path': 'Shared Queries',
          'isFolder': true,
          'children': [
            {
              'id': 'q1',
              'name': 'Open bugs',
              'path': 'Shared Queries/Open bugs',
              'isFolder': false,
            },
            {
              'id': 'f1',
              'name': 'Triage',
              'path': 'Shared Queries/Triage',
              'isFolder': true,
              'children': [
                {
                  'id': 'q2',
                  'name': 'Untriaged',
                  'path': 'Shared Queries/Triage/Untriaged',
                  'isFolder': false,
                },
              ],
            },
          ],
        }),
      ];
      final leaves = [for (final r in tree) ...r.leaves];
      expect(leaves.map((q) => q.id), ['q1', 'q2']);
      expect(leaves[1].folder, 'Shared Queries/Triage');
    });

    test('ids from flat and tree query results', () {
      expect(
        WorkItemRepository.idsFromQueryResult({
          'queryType': 'flat',
          'workItems': [
            {'id': 3},
            {'id': 1},
          ],
        }),
        [3, 1],
      );
      expect(
        WorkItemRepository.idsFromQueryResult({
          'queryType': 'tree',
          'workItemRelations': [
            {
              'target': {'id': 10},
            },
            {
              'source': {'id': 10},
              'target': {'id': 11},
            },
            {
              'source': {'id': 10},
              'target': {'id': 11},
            },
          ],
        }),
        [10, 11],
      );
    });
  });

  group('format helpers', () {
    test('relativeTime', () {
      final now = DateTime(2026, 9, 10, 12);
      expect(
        relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
        'just now',
      );
      expect(
        relativeTime(now.subtract(const Duration(minutes: 3)), now: now),
        '3m',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 5)), now: now),
        '5h',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d',
      );
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

  group('avatars', () {
    test('IdentityRef keeps the descriptor and derives the org', () {
      final ref = IdentityRef.fromJson({
        'displayName': 'Kelly Kamm',
        'id': 'k',
        'descriptor': 'aad.abc',
        'imageUrl': 'https://dev.azure.com/o/_api/_common/identityImage?id=k',
        '_links': {
          'avatar': {
            'href': 'https://dev.azure.com/o/_apis/GraphProfile/MemberAvatars/aad.abc',
          },
        },
      });
      expect(ref.org, 'o');
      final source = ref.avatarSource()!;
      expect(source.isGraph, isTrue);
      expect(source.key, 'graph:o:aad.abc:medium');
      expect(ref.avatarSource(size: AvatarSize.large)!.key, endsWith(':large'));
      // Without a descriptor the image link is the fallback.
      final noDescriptor = IdentityRef.fromJson({
        'displayName': 'X',
        'imageUrl': 'https://dev.azure.com/o/_api/_common/identityImage?id=x',
      });
      expect(noDescriptor.avatarSource()!.isGraph, isFalse);
      expect(noDescriptor.avatarSource()!.url, noDescriptor.imageUrl);
      expect(const IdentityRef(displayName: 'n').avatarSource(), isNull);
      expect(const IdentityRef(displayName: 'n').org, isNull);
    });

    test('cache file names come from the source key', () {
      expect(
        AvatarStore.fileNameFor(
          AvatarSource.graph(
            org: 'o',
            descriptor: 'aad.NWVk',
            size: AvatarSize.small,
          ),
        ),
        'graph_o_aad.NWVk_small.png',
      );
      expect(
        AvatarStore.fileNameFor(AvatarSource.url('https://x/y?id=1')),
        'url_https___x_y_id_1.png',
      );
    });
  });

  group('AccountHeader', () {
    test('from Graph me + organization, and json round trip', () {
      final h = AccountHeader.fromGraph(
        {'displayName': 'Kelly Kamm', 'mail': 'kkamm@cloudcover.it'},
        {'displayName': 'CloudCover IoT, Inc'},
      );
      expect(h.email, 'kkamm@cloudcover.it');
      expect(h.organizationName, 'CloudCover IoT, Inc');
      expect(AccountHeader.fromJson(h.toJson()), h);
      final upn = AccountHeader.fromGraph({
        'displayName': 'X',
        'userPrincipalName': 'x@y.z',
      }, null);
      expect(upn.email, 'x@y.z');
      expect(upn.organizationName, isNull);
    });
  });
}
