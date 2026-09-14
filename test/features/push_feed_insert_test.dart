import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/notifications/notification_service.dart';
import 'package:boardhop/data/activity_sync.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/db/json_cache.dart';
import 'package:boardhop/data/models/activity.dart';
import 'package:boardhop/data/repositories/activity_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/features/notifications/push_background.dart';
import 'package:boardhop/features/notifications/push_coordinator.dart';
import 'package:boardhop/features/notifications/push_pointer.dart';
import 'package:boardhop/features/notifications/push_registrar.dart';
import 'package:boardhop/features/notifications/push_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'account-1';
const org = 'contoso';

PushPointer pointer({
  String org = org,
  String artifactType = 'pullRequest',
  String artifactId = '8336',
  String? verb = 'replied',
  String? runId,
}) => PushPointer.tryFrom({
  'org': org,
  'eventType': 'ms.vss-code.git-pullrequest-comment-event',
  'artifactType': artifactType,
  'artifactId': artifactId,
  'project': 'DevOps Mobile App',
  'actor': 'Ada Example',
  'actorId': 'ada-id',
  'verb': ?verb,
  'runId': ?runId,
  'anchor': 'thread:4821',
  'sentAt': DateTime.utc(2026, 9, 13, 10).toIso8601String(),
  'collapseKey': 'contoso.pr.8336.t4821',
  'fallbackTitle': '!8336 · Wire up the relay',
  'fallbackBody': 'Ada Example replied on !8336',
})!;

void main() {
  late AppDatabase db;
  late ActivityRepository repository;
  late JsonCache cache;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
    );
    repository = ActivityRepository(
      client,
      db,
      PullRequestRepository(client, db, account),
      PipelineRepository(client, db, account),
      userId: account,
    );
    cache = JsonCache(db, namespace: account);
  });

  tearDown(() => db.close());

  group('a pointer becomes a feed row', () {
    test('a pull request comment is review-side', () {
      final item = pushedActivityItem(pointer(), account)!;
      expect(item.kind, ActivityKind.prReview);
      expect(item.key, 'pr:8336');
      expect(item.title, '!8336 · Wire up the relay');
      expect(item.subtitle, 'Ada Example replied on !8336');
      expect(item.actor, 'Ada Example');
      expect(item.actorId, 'ada-id');
      expect(
        item.route,
        '/a/account-1/orgs/contoso/pull-requests/8336?thread=4821',
      );
      expect(item.time, DateTime.utc(2026, 9, 13, 10).toLocal());
    });

    test('what happens to a pull request of mine is prMine', () {
      expect(
        pushedActivityItem(pointer(verb: 'voted'), account)!.kind,
        ActivityKind.prMine,
      );
      expect(
        pushedActivityItem(pointer(verb: 'prCompleted'), account)!.kind,
        ActivityKind.prMine,
      );
      expect(
        pushedActivityItem(pointer(verb: 'reviewRequested'), account)!.kind,
        ActivityKind.prReview,
      );
    });

    test('work items, builds and approvals take their own kind', () {
      expect(
        pushedActivityItem(
          pointer(artifactType: 'workItem', artifactId: '15545'),
          account,
        )!.kind,
        ActivityKind.workItem,
      );
      expect(
        pushedActivityItem(
          pointer(artifactType: 'build', artifactId: '20163'),
          account,
        )!.kind,
        ActivityKind.build,
      );
      final approval = pushedActivityItem(
        pointer(artifactType: 'approval', artifactId: '18', runId: '20163'),
        account,
      )!;
      expect(approval.kind, ActivityKind.build);
      expect(approval.key, 'build:20163');
    });

    test('the test push has no row to insert', () {
      expect(
        pushedActivityItem(
          pointer(artifactType: 'approval', artifactId: '18'),
          account,
        ),
        isNull,
      );
    });
  });

  group('inserting it', () {
    test('puts it at the top of the cached feed', () async {
      await repository.insertPushed(
        org,
        pushedActivityItem(pointer(), account)!,
      );
      final cached = await repository.cached(org);
      expect(cached!.items.single.key, 'pr:8336');
    });

    test(
      'the next copy of the same artifact replaces it, never doubles it',
      () async {
        await repository.insertPushed(
          org,
          pushedActivityItem(pointer(), account)!,
        );
        await repository.insertPushed(
          org,
          pushedActivityItem(pointer(verb: 'voted'), account)!,
        );
        final cached = await repository.cached(org);
        expect(cached!.items.length, 1);
        expect(cached.items.single.kind, ActivityKind.prMine);
      },
    );

    test(
      'does not mark the feed seen: the row is new until it is opened',
      () async {
        await repository.insertPushed(
          org,
          pushedActivityItem(pointer(), account)!,
        );
        expect(await repository.lastSeen(org), isNull);
      },
    );

    test(
      'announces the key, so the poll does not notify a second time',
      () async {
        final item = pushedActivityItem(pointer(), account)!;
        await repository.insertPushed(org, item);

        final remembered = await cache.get(ActivityRepository.notifiedKey(org));
        final notified = <String>{
          if (remembered?.json case final List l) ...l.map((e) => e.toString()),
        };
        expect(notified, contains('pr:8336'));

        // The poll now sees the same artifact, newer than the last visit and
        // not caused by this user — and still says nothing about it.
        expect(
          ActivitySync.toNotify(
            [item],
            lastSeen: DateTime.utc(2026, 9, 13, 9),
            notified: notified,
            meId: 'someone-else',
          ),
          isEmpty,
        );
        // Without the push having been announced it would have notified.
        expect(
          ActivitySync.toNotify(
            [item],
            lastSeen: DateTime.utc(2026, 9, 13, 9),
            notified: const {},
            meId: 'someone-else',
          ),
          [item],
        );
      },
    );

    test('keeps the keys another org announced', () async {
      await repository.insertPushed(
        org,
        pushedActivityItem(pointer(), account)!,
      );
      await repository.insertPushed(
        org,
        pushedActivityItem(
          pointer(artifactType: 'workItem', artifactId: '15545'),
          account,
        )!,
      );
      final remembered = await cache.get(ActivityRepository.notifiedKey(org));
      expect(remembered!.json, containsAll(['pr:8336', 'wi:15545']));
    });

    test('the sync and the repository agree on the key', () {
      expect(ActivitySync.notifiedKey(org), 'activity:notified:contoso');
      expect(
        ActivityRepository.notifiedKey(org),
        ActivitySync.notifiedKey(org),
      );
    });
  });

  group('pointers the platform posted while Dart was not running', () {
    late PushService push;
    late PushCoordinator coordinator;
    late NotificationService notifications;

    setUp(() async {
      notifications = NotificationService.fake();
      push = PushService.fake();
      final registrar = PushRegistrar(
        accountId: account,
        accessToken: () async => 'tok',
      );
      addTearDown(registrar.dispose);
      coordinator = PushCoordinator(
        push: push,
        notifications: notifications,
        registrarFor: (_) => registrar,
        orgFor: (_) async => org,
        openRoute: (_) {},
        activityFor: (_) => repository,
      );
      await coordinator.syncAccounts(const [account]);
    });

    tearDown(() {
      coordinator.dispose();
      notifications.dispose();
    });

    Future<Set<String>> notified() async {
      final remembered = await cache.get(ActivityRepository.notifiedKey(org));
      return {
        if (remembered?.json case final List l) ...l.map((e) => e.toString()),
      };
    }

    test('a drain files each one in the feed and marks it announced', () async {
      push.fakePending = [
        pointer(),
        pointer(artifactType: 'approval', artifactId: '18', runId: '20163'),
      ];
      await coordinator.drainPushed();

      final keys = (await repository.cached(org))!.items.map((i) => i.key);
      expect(keys, containsAll(['pr:8336', 'build:20163']));
      expect(await notified(), containsAll(['pr:8336', 'build:20163']));
      // Taken once: the platform emptied its queue.
      expect(push.fakePending, isEmpty);
    });

    test('the poll then stays quiet about the pushed approval', () async {
      final approval = pointer(
        artifactType: 'approval',
        artifactId: '18',
        runId: '20163',
      );
      push.fakePending = [approval];
      await coordinator.drainPushed();
      final item = pushedActivityItem(approval, account)!;
      expect(
        ActivitySync.toNotify(
          [item],
          lastSeen: DateTime.utc(2026, 9, 13, 9),
          notified: await notified(),
          meId: 'someone-else',
        ),
        isEmpty,
      );
    });

    test('a pointer for an org no account owns is dropped', () async {
      push.fakePending = [pointer(org: 'someone-elses-org')];
      await coordinator.drainPushed();
      expect(await repository.cached(org), isNull);
      expect(push.fakePending, isEmpty);
    });

    test('with no accounts yet the queue stays on the platform', () async {
      push.fakePending = [pointer()];
      await coordinator.syncAccounts(const []);
      await coordinator.drainPushed();
      // Not taken, not lost: the next account sync files it.
      expect(push.fakePending, hasLength(1));
      expect(await repository.cached(org), isNull);

      await coordinator.syncAccounts(const [account]);
      expect(push.fakePending, isEmpty);
      expect((await repository.cached(org))!.items.single.key, 'pr:8336');
    });

    test('start drains too', () async {
      push.fakePending = [pointer()];
      coordinator.start();
      await pumpEventQueue();
      expect((await repository.cached(org))!.items.single.key, 'pr:8336');
    });
  });

  group('a pushed row outlives the poll', () {
    final now = DateTime.utc(2026, 9, 14, 12);

    test('is flagged, and the flag survives the JSON cache', () {
      final item = pushedActivityItem(pointer(), account)!;
      expect(item.pushed, isTrue);
      final back = ActivityItem.fromJson(item.toJson());
      expect(back.pushed, isTrue);
      expect(back.key, item.key);
      // The poll's own rows are not.
      expect(
        ActivityItem.fromJson({'kind': 'build', 'key': 'build:1'}).pushed,
        isFalse,
      );
    });

    test('refresh keeps a young pushed row the sources did not list', () {
      final pushedRow = pushedActivityItem(
        pointer(artifactType: 'build', artifactId: '20171'),
        account,
      )!;
      final kept = ActivityRepository.withPushed(const [], [
        pushedRow,
      ], now: now);
      expect(kept.map((i) => i.key), ['build:20171']);
    });

    test('drops a pushed row older than the window, and unpushed rows', () {
      final old = ActivityItem(
        kind: ActivityKind.build,
        key: 'build:1',
        title: 'old',
        subtitle: '',
        route: '',
        time: now.subtract(const Duration(days: 8)),
        pushed: true,
      );
      final polled = ActivityItem(
        kind: ActivityKind.build,
        key: 'build:2',
        title: 'polled last time',
        subtitle: '',
        route: '',
        time: now,
      );
      expect(
        ActivityRepository.withPushed(const [], [old, polled], now: now),
        isEmpty,
      );
    });

    test('a fetched copy of the same key wins over the pushed one', () {
      final pushedRow = pushedActivityItem(pointer(), account)!;
      final fetched = ActivityItem(
        kind: ActivityKind.prReview,
        key: 'pr:8336',
        title: 'fetched',
        subtitle: '',
        route: '',
        time: now,
      );
      final merged = ActivityRepository.withPushed(
        [fetched],
        [pushedRow],
        now: now,
      );
      expect(merged.single.title, 'fetched');
      expect(merged.single.pushed, isFalse);
    });
  });

  group('a tap on a background-posted notification', () {
    late List<String> opened;
    late PushCoordinator coordinator;
    late NotificationService notifications;

    setUp(() async {
      opened = [];
      notifications = NotificationService.fake();
      final registrar = PushRegistrar(
        accountId: account,
        accessToken: () async => 'tok',
      );
      addTearDown(registrar.dispose);
      coordinator = PushCoordinator(
        push: PushService.fake(),
        notifications: notifications,
        registrarFor: (_) => registrar,
        orgFor: (_) async => org,
        openRoute: opened.add,
        activityFor: (_) => repository,
      );
      await coordinator.syncAccounts(const [account]);
    });

    tearDown(() {
      coordinator.dispose();
      notifications.dispose();
    });

    test('routes through the pointer, anchor and all', () async {
      final payload = pushPayloadFor(pointer());
      expect(coordinator.handleTapPayload(payload), isTrue);
      expect(opened, [
        '/a/account-1/orgs/contoso/pull-requests/8336?thread=4821',
      ]);
      // …and the feed has the row, whether or not the poll has run.
      await Future<void>.delayed(Duration.zero);
      expect((await repository.cached(org))!.items.single.key, 'pr:8336');
    });

    test('an ordinary route payload is left to the caller', () {
      expect(
        coordinator.handleTapPayload('/a/account-1/orgs/contoso/activity'),
        isFalse,
      );
      expect(opened, isEmpty);
    });

    test('a malformed pointer payload opens nothing', () {
      expect(coordinator.handleTapPayload('push:{broken'), isTrue);
      expect(opened, isEmpty);
    });
  });
}
