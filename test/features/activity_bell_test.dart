import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/activity.dart';
import 'package:boardhop/data/repositories/activity_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/features/activity/activity_bell.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'root_tab_stubs.dart';

const _account = 'u1';
const _org = 'contoso';

ActivityItem _item(DateTime time) => ActivityItem(
  kind: ActivityKind.prReview,
  key: 'pr:8336',
  title: 'Wire up the relay',
  subtitle: 'DevOps Mobile App · !8336',
  route: '${Routes.org(_account, _org)}/pull-requests/8336',
  time: time,
  pushed: true,
);

void main() {
  group('ActivityRepository.unread', () {
    late AppDatabase db;
    late ActivityRepository repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final client = AdoClient(
        tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      );
      repository = ActivityRepository(
        client,
        db,
        PullRequestRepository(client, db, _account),
        PipelineRepository(client, db, _account),
        userId: _account,
      );
    });

    tearDown(() => db.close());

    test('counts the cached items newer than the seen marker', () async {
      await repository.markSeen(_org, DateTime.utc(2026, 9, 15, 10));
      await repository.insertPushed(_org, _item(DateTime.utc(2026, 9, 15, 11)));

      expect(await repository.unread(_org).first, 1);

      // Opening the feed marks everything seen, and the bell clears.
      await repository.markSeen(_org, DateTime.utc(2026, 9, 15, 12));
      expect(await repository.unread(_org).first, 0);
    });

    test('re-emits when the feed or the seen marker changes', () async {
      final becomesOne = expectLater(repository.unread(_org), emitsThrough(1));
      await repository.markSeen(_org, DateTime.utc(2026, 9, 15, 10));
      await repository.insertPushed(_org, _item(DateTime.utc(2026, 9, 15, 11)));
      await becomesOne;
    });

    test('an organization that was never opened has nothing new', () async {
      expect(await repository.unread('fabrikam').first, 0);
    });
  });

  group('the bell', () {
    Future<List<String>> pump(
      WidgetTester tester, {
      required int unread,
    }) async {
      final pushed = <String>[];
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              appBar: AppBar(actions: const [ActivityBell(org: _org)]),
            ),
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/activity',
            builder: (_, state) {
              pushed.add(state.uri.toString());
              return const Scaffold(body: Text('activity page'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: rootChromeProviders(
            activity: stubActivity(unread: unread),
          ),
          child: MaterialApp.router(
            theme: BoardhopTheme.light(),
            routerConfig: router,
            builder: (context, child) =>
                AccountScope(accountId: _account, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return pushed;
    }

    testWidgets('carries a dot and says how many while something is new', (
      tester,
    ) async {
      final pushed = await pump(tester, unread: 4);

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.byTooltip('Activity · 4 new'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(pushed, [Routes.activity(_account, _org)]);
      expect(find.text('activity page'), findsOneWidget);
    });

    testWidgets('has no dot when nothing is new', (tester) async {
      await pump(tester, unread: 0);

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);
      expect(find.byTooltip('Activity'), findsOneWidget);
    });
  });
}
