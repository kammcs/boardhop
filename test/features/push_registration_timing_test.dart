import 'dart:async';

import 'package:boardhop/core/notifications/notification_service.dart';
import 'package:boardhop/features/notifications/push_coordinator.dart';
import 'package:boardhop/features/notifications/push_registrar.dart';
import 'package:boardhop/features/notifications/push_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registration with the relay follows the user's grant of the notification
/// permission, not the next app start (Kelly, 2026-09-14): on iOS the token
/// arrives asynchronously after `register`, so the "Turn on" flow waits for
/// it, and coming back to the foreground registers whatever is still missing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const account = 'kelly@kammcs.com-home';
  const org = 'contoso';
  const channel = PushService.channel;

  setUp(() => PushService.platformOverride = 'ios');
  tearDown(() {
    PushService.platformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PushService.refreshToken on iOS', () {
    test('waits for the token that follows register', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            // The Runner has no token yet: APNs answers later.
            return call.method == 'register' ? null : null;
          });
      final service = PushService.fake();
      final pending = service.refreshToken();
      // The APNs token arriving as `onToken` a moment later.
      Timer(const Duration(milliseconds: 50), () {
        service.token.value = 'apns-token-1';
      });
      expect(await pending, 'apns-token-1');
    });

    test('answers at once when the Runner already holds a token', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return call.method == 'register' ? 'apns-token-0' : null;
          });
      final service = PushService.fake();
      expect(await service.refreshToken(), 'apns-token-0');
      expect(service.token.value, 'apns-token-0');
    });
  });

  group('PushCoordinator', () {
    late List<({String method, Uri url})> calls;
    late List<RelayResponse> answers;
    late NotificationService notifications;
    late PushService push;
    late PushRegistrar registrar;
    late PushCoordinator coordinator;

    setUp(() async {
      calls = [];
      answers = [];
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return call.method == 'register' ? 'apns-token-2' : true;
          });
      notifications = NotificationService.fake();
      push = PushService.fake();
      registrar = PushRegistrar(
        accountId: account,
        accessToken: () async => 'ado',
        prefs: await SharedPreferences.getInstance(),
        relayUrl: (_) => 'https://relay.test',
        call:
            (method, url, {String? bearer, Map<String, Object?>? body}) async {
              calls.add((method: method, url: url));
              return answers.isEmpty
                  ? const RelayResponse(200, {'deviceId': 'device-1'})
                  : answers.removeAt(0);
            },
      );
      coordinator = PushCoordinator(
        push: push,
        notifications: notifications,
        registrarFor: (_) => registrar,
        orgFor: (_) async => org,
        openRoute: (_) {},
      )..start();
      await coordinator.syncAccounts(const [account]);
    });

    tearDown(() {
      coordinator.dispose();
      notifications.dispose();
      registrar.dispose();
    });

    List<String> posts() => [
      for (final c in calls)
        if (c.method == 'POST') c.url.path,
    ];

    test(
      'registers when the permission is granted, without a restart',
      () async {
        expect(posts(), isEmpty);
        await notifications.setEnabled(true);
        await pumpEventQueue();
        expect(posts(), ['/v1/devices']);
        expect(registrar.registration.value?.org, org);
      },
    );

    test('a resume registers what the relay refused earlier', () async {
      answers.add(const RelayResponse(503));
      await notifications.setEnabled(true);
      await pumpEventQueue();
      expect(posts(), ['/v1/devices']);
      expect(registrar.registration.value, isNull);

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      expect(posts(), ['/v1/devices', '/v1/devices']);
      expect(registrar.registration.value?.deviceId, 'device-1');
    });

    test('a resume of a registered phone is at most a heartbeat', () async {
      await notifications.setEnabled(true);
      await pumpEventQueue();
      expect(posts(), ['/v1/devices']);

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      // The heartbeat is once a day; a registration seconds old sends nothing.
      expect(posts(), ['/v1/devices']);
    });
  });
}
