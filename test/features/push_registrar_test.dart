import 'package:boardhop/features/notifications/push_registrar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = 'kelly@kammcs.com-home';
const deviceToken = 'fcm-token-abcdefghijklmnopqrstuvwxyz-012345';

/// Records what the registrar sent and answers with a queued response.
class FakeRelay {
  final List<
    ({String method, Uri url, String? bearer, Map<String, Object?>? body})
  >
  calls = [];
  final List<RelayResponse> answers = [];

  /// Used once the queue runs out.
  RelayResponse fallback = const RelayResponse(200, {'deviceId': 'device-1'});

  RelayCall get call =>
      (method, url, {String? bearer, Map<String, Object?>? body}) async {
        calls.add((method: method, url: url, bearer: bearer, body: body));
        return answers.isEmpty ? fallback : answers.removeAt(0);
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRelay relay;
  late PushRegistrar registrar;
  var tokenCalls = 0;

  Future<PushRegistrar> build({bool tokenFails = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return PushRegistrar(
      accountId: account,
      accessToken: () async {
        tokenCalls++;
        if (tokenFails) throw StateError('no token');
        return 'ado-access-token';
      },
      call: relay.call,
      prefs: prefs,
      relayUrl: (org) => 'https://relay.test',
    );
  }

  setUp(() async {
    relay = FakeRelay();
    tokenCalls = 0;
    registrar = await build();
  });

  group('register', () {
    test('posts the device and remembers what came back', () async {
      final registration = await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      expect(registration!.deviceId, 'device-1');
      expect(registration.org, 'puremedia');
      expect(registrar.registration.value, isNotNull);

      final call = relay.calls.single;
      expect(call.method, 'POST');
      expect(call.url.toString(), 'https://relay.test/v1/devices');
      expect(call.bearer, 'ado-access-token');
      expect(call.body!['token'], deviceToken);
      expect(call.body!['platform'], 'android');
      expect(call.body!['appVersion'], isNotEmpty);
    });

    test('survives a reload: the record is in shared preferences', () async {
      await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      final again = PushRegistrar(
        accountId: account,
        accessToken: () async => 'ado-access-token',
        call: relay.call,
        prefs: await SharedPreferences.getInstance(),
      );
      final loaded = await again.load();
      expect(loaded!.deviceId, 'device-1');
    });

    test('a 401 drops the record so the next start tries again', () async {
      relay.answers.add(const RelayResponse(401, {'error': 'unauthorized'}));
      final registration = await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      expect(registration, isNull);
      expect(registrar.registration.value, isNull);

      // The retry, with a refreshed token, succeeds and is remembered.
      final retry = await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      expect(retry, isNotNull);
      expect(await registrar.load(), isNotNull);
    });

    test('a relay that answers nonsense is not remembered', () async {
      relay.answers.add(const RelayResponse(200, {'nothing': true}));
      expect(
        await registrar.register(
          org: 'puremedia',
          platform: 'android',
          token: deviceToken,
        ),
        isNull,
      );
    });

    test('no access token means no call at all', () async {
      registrar = await build(tokenFails: true);
      expect(
        await registrar.register(
          org: 'puremedia',
          platform: 'android',
          token: deviceToken,
        ),
        isNull,
      );
      expect(relay.calls, isEmpty);
      expect(tokenCalls, 1);
    });
  });

  group('heartbeat', () {
    Future<void> registerFirst() async {
      await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      relay.calls.clear();
    }

    test('is skipped while the last one is less than a day old', () async {
      await registerFirst();
      await registrar.heartbeat(token: deviceToken);
      expect(relay.calls, isEmpty);
    });

    test(
      'posts to the device once a day and carries a rotated token',
      () async {
        await registerFirst();
        relay.fallback = const RelayResponse(200, {'deviceId': 'device-1'});
        await registrar.heartbeat(
          token: 'rotated-token-zyxwvutsrqponmlkjihgfedcba-987',
          now: DateTime.now().add(const Duration(days: 2)),
        );
        final call = relay.calls.single;
        expect(call.method, 'POST');
        expect(call.url.path, '/v1/devices/device-1/heartbeat');
        expect(
          call.body!['token'],
          'rotated-token-zyxwvutsrqponmlkjihgfedcba-987',
        );
        expect(registrar.registration.value, isNotNull);
      },
    );

    test('a 404 or 401 forgets the device', () async {
      await registerFirst();
      relay.answers.add(const RelayResponse(404, {'error': 'unknown device'}));
      await registrar.heartbeat(
        token: deviceToken,
        now: DateTime.now().add(const Duration(days: 2)),
      );
      expect(registrar.registration.value, isNull);
      expect(await registrar.load(), isNull);
    });

    test('does nothing when nothing was registered', () async {
      await registrar.heartbeat(token: deviceToken);
      expect(relay.calls, isEmpty);
    });
  });

  group('unregister', () {
    test('deletes on the relay and locally', () async {
      await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      relay.calls.clear();
      relay.fallback = const RelayResponse(204);

      await registrar.unregister();
      final call = relay.calls.single;
      expect(call.method, 'DELETE');
      expect(call.url.path, '/v1/devices/device-1');
      expect(registrar.registration.value, isNull);
      expect(await registrar.load(), isNull);
    });

    test('forgets locally even when the relay refuses', () async {
      await registrar.register(
        org: 'puremedia',
        platform: 'android',
        token: deviceToken,
      );
      relay.answers.add(const RelayResponse(500));
      await registrar.unregister();
      expect(await registrar.load(), isNull);
    });
  });

  group('test push', () {
    test('asks the relay and reports how many devices were woken', () async {
      relay.fallback = const RelayResponse(200, {'devices': 2, 'sent': 2});
      expect(await registrar.sendTestPush(org: 'puremedia'), 2);
      final call = relay.calls.single;
      expect(call.url.path, '/v1/test-push');
      expect(call.body, {'org': 'puremedia'});
    });

    test('null when the relay could not send', () async {
      relay.answers.add(const RelayResponse(404, {'error': 'no devices'}));
      expect(await registrar.sendTestPush(org: 'puremedia'), isNull);
    });
  });
}
