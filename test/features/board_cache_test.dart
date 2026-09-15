import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/db/json_cache.dart';
import 'package:boardhop/data/models/board.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/board_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/boards/boards_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'contoso';
const project = 'Scratch';
const boardId = 'b0000000-1111-2222-3333-444444444444';

/// Every request fails the way an offline phone does, which is the whole
/// point of the cache (decision S9).
class _OfflineAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'no route to host',
    );
  }

  @override
  void close({bool force = false}) {}
}

Board board() => Board.fromJson({
  'id': boardId,
  'name': 'Stories',
  'columns': [
    {
      'id': 'c-new',
      'name': 'New',
      'columnType': 'incoming',
      'stateMappings': {'User Story': 'New'},
    },
    {
      'id': 'c-active',
      'name': 'Active',
      'columnType': 'inProgress',
      'stateMappings': {'User Story': 'Active'},
    },
  ],
  'rows': [
    {'id': null, 'name': null},
  ],
  'fields': {
    'columnField': {'referenceName': 'WEF_1_Kanban.Column'},
    'doneField': {'referenceName': 'WEF_1_Kanban.Column.Done'},
  },
  'allowedMappings': {
    'inProgress': {
      'User Story': ['Active'],
    },
  },
  'canEdit': true,
  'isValid': true,
});

WorkItem card(int id, String title, String state) => WorkItem.fromJson({
  'id': id,
  'rev': 2,
  'fields': {
    'System.Id': id,
    'System.WorkItemType': 'User Story',
    'System.Title': title,
    'System.State': state,
  },
});

BoardSnapshot snapshot({DateTime? at}) => BoardSnapshot(
  board: board(),
  cardsBySlot: [
    [card(1, 'Cached story one', 'New')],
    [card(2, 'Cached story two', 'Active')],
  ],
  fetchedAt: at ?? DateTime.now().subtract(const Duration(minutes: 3)),
  rankField: BoardRepository.stackRank,
);

void main() {
  late AppDatabase db;
  late _OfflineAdapter adapter;
  late BoardRepository boards;
  late WorkItemRepository workItems;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    adapter = _OfflineAdapter();
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    );
    workItems = WorkItemRepository(client, db, userId: account);
    boards = BoardRepository(client, workItems, db, account);
  });

  tearDown(() => db.close());

  Future<void> seed({DateTime? at}) => JsonCache(db, namespace: account).put(
    BoardRepository.snapshotKey(org, project, boardId),
    snapshot(at: at).toJson(),
  );

  group('BoardSnapshot', () {
    test('round trips through JSON', () {
      final live = snapshot(at: DateTime.utc(2026, 9, 15, 9));

      final back = BoardSnapshot.fromJson(
        (jsonDecode(jsonEncode(live.toJson())) as Map).cast<String, dynamic>(),
      );

      expect(back.board, live.board);
      expect(back.board.columns.first.stateMappings, {'User Story': 'New'});
      expect(back.board.fields.columnField, 'WEF_1_Kanban.Column');
      expect(back.board.fields.rowField, isNull);
      expect(back.board.allowedMappings, live.board.allowedMappings);
      expect(back.rankField, BoardRepository.stackRank);
      expect(back.fetchedAt, live.fetchedAt);
      expect(back.cardsBySlot.length, 2);
      expect(back.cardCount, 2);
      expect(back.cardsBySlot.first.single.title, 'Cached story one');
    });
  });

  group('cachedSnapshot', () {
    test('answers the board it was stored under', () async {
      await seed();

      final cached = await boards.cachedSnapshot(org, project, boardId);

      expect(cached, isNotNull);
      expect(cached!.board.name, 'Stories');
      expect(cached.cardCount, 2);
    });

    test('with no board id it answers the last board read', () async {
      await seed();

      final cached = await boards.cachedSnapshot(org, project);

      expect(cached!.board.id, boardId);
    });

    test('null when nothing was ever cached', () async {
      expect(await boards.cachedSnapshot(org, project), isNull);
      expect(await boards.cachedSnapshot(org, project, boardId), isNull);
    });
  });

  group('BoardsPage offline', () {
    Widget app() => MaterialApp(
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BoardRepository>.value(value: boards),
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
        ],
        child: const AccountScope(
          accountId: account,
          child: BoardsPage(org: org, project: project),
        ),
      ),
    );

    testWidgets('draws the cached cards and says where they came from', (
      tester,
    ) async {
      await seed();

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Before the fix this was a spinner and then an error strip: the
      // cards were written to drift and never read back.
      expect(find.text('Cached story one'), findsOneWidget);
      expect(find.text('Cached story two'), findsOneWidget);
      expect(find.text('Stories'), findsOneWidget);
      expect(
        find.textContaining('offline · showing the cached copy'),
        findsOneWidget,
      );
      expect(find.textContaining('3m'), findsOneWidget);
      // The network failure is not an error strip while there are cards.
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(adapter.requests, greaterThan(0));
    });

    testWidgets('with nothing cached it still shows the error', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(
        find.textContaining('offline · showing the cached copy'),
        findsNothing,
      );
    });
  });
}
