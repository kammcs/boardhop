import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/push_prefs.dart';
import 'package:boardhop/data/repositories/push_prefs_repository.dart';
import 'package:boardhop/features/notifications/push_registrar.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'contoso';

/// Records what the repository sent and answers with a queued response.
class FakeRelay {
  final List<
    ({String method, Uri url, String? bearer, Map<String, Object?>? body})
  >
  calls = [];
  final List<RelayResponse> answers = [];
  RelayResponse fallback = const RelayResponse(200, {});

  RelayCall get call =>
      (method, url, {String? bearer, Map<String, Object?>? body}) async {
        calls.add((method: method, url: url, bearer: bearer, body: body));
        return answers.isEmpty ? fallback : answers.removeAt(0);
      };
}

void main() {
  late FakeRelay relay;
  late AppDatabase db;

  PushPrefsRepository build({bool tokenFails = false}) => PushPrefsRepository(
    accountId: account,
    accessToken: () async {
      if (tokenFails) throw StateError('no token');
      return 'ado-access-token';
    },
    call: relay.call,
    db: db,
    relayUrl: (_) => 'https://relay.test',
  );

  setUp(() {
    relay = FakeRelay();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('GET', () {
    test('asks for the org with the account token as the bearer', () async {
      relay.answers.add(
        RelayResponse(200, PushPrefs.fromDefaults().toJson()),
      );
      final result = await build().fetch(org);

      expect(relay.calls.single.method, 'GET');
      expect(
        relay.calls.single.url.toString(),
        'https://relay.test/v1/prefs?org=contoso',
      );
      expect(relay.calls.single.bearer, 'ado-access-token');
      expect(result.status, PushPrefsStatus.ok);
      expect(result.prefs!.builds, BuildPref.failuresAndFixed);
    });

    test('caches what came back, so the screen opens offline', () async {
      relay.answers.add(
        RelayResponse(
          200,
          PushPrefs.fromDefaults().copyWith(builds: BuildPref.all).toJson(),
        ),
      );
      final repository = build();
      await repository.fetch(org);
      expect((await repository.cached(org))!.builds, BuildPref.all);

      // The relay is unreachable now: the cached copy is what is shown, and
      // the caller is told it is not fresh.
      relay.answers.add(const RelayResponse(500));
      final offline = await repository.fetch(org);
      expect(offline.status, PushPrefsStatus.failed);
      expect(offline.fromCache, isTrue);
      expect(offline.prefs!.builds, BuildPref.all);
    });

    test('404 is "unavailable", not "the defaults are in force"', () async {
      relay.answers.add(const RelayResponse(404));
      final result = await build().fetch(org);
      expect(result.status, PushPrefsStatus.unavailable);
      expect(result.prefs, isNull);
    });

    test('a token that cannot be acquired is a failure, not a throw', () async {
      final result = await build(tokenFails: true).fetch(org);
      expect(result.status, PushPrefsStatus.failed);
      expect(relay.calls, isEmpty);
    });
  });

  group('PUT', () {
    test('sends the whole document without notActor', () async {
      relay.answers.add(
        RelayResponse(
          200,
          PushPrefs.fromDefaults().copyWith(approvals: false).toJson(),
        ),
      );
      final result = await build().save(
        org,
        PushPrefs.fromDefaults().copyWith(approvals: false),
      );

      final sent = relay.calls.single;
      expect(sent.method, 'PUT');
      expect(sent.url.queryParameters['org'], org);
      expect(sent.body!['approvals'], false);
      expect(sent.body!.containsKey('notActor'), isFalse);
      expect(result.ok, isTrue);
      expect(result.prefs!.approvals, isFalse);
    });

    test('the stored document the relay answers with is what is cached',
        () async {
      relay.answers.add(
        RelayResponse(
          200,
          PushPrefs.fromDefaults()
              .copyWith(
                mutedArtifacts: [const MutedArtifact(type: 'pr', id: '8336')],
              )
              .toJson(),
        ),
      );
      final repository = build();
      await repository.save(org, PushPrefs.fromDefaults());
      expect((await repository.cached(org))!.mutedArtifacts.single.key,
          'pr.8336');
    });

    test('a refusal is reported so the screen can put the row back', () async {
      relay.answers.add(
        const RelayResponse(400, {'error': 'unknown preference "buidls"'}),
      );
      expect(
        (await build().save(org, PushPrefs.fromDefaults())).status,
        PushPrefsStatus.failed,
      );
    });

    test('404 from an older relay is unavailable', () async {
      relay.answers.add(const RelayResponse(404));
      expect(
        (await build().save(org, PushPrefs.fromDefaults())).status,
        PushPrefsStatus.unavailable,
      );
    });
  });
}
