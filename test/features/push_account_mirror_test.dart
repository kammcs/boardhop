import 'package:boardhop/features/notifications/push_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart half of R2.7's account mirror: what `PushService.mirrorAccount`
/// puts on the `com.kammcs.boardhop/push` channel, which is what
/// `AppDelegate.swift` turns into a write in the app group
/// `BoardhopNotificationService` reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late PushService push;

  setUp(() {
    calls = [];
    push = PushService.fake();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushService.channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushService.channel, null);
  });

  test('an account id is set for its organization', () async {
    await push.mirrorAccount('puremedia', 'kelly@kammcs.com-home');
    expect(calls.single.method, 'setAccount');
    expect(calls.single.arguments, {
      'org': 'puremedia',
      'accountId': 'kelly@kammcs.com-home',
    });
  });

  test('null clears it', () async {
    await push.mirrorAccount('puremedia', null);
    expect(calls.single.method, 'clearAccount');
    expect(calls.single.arguments, {'org': 'puremedia'});
  });

  test('an empty account id clears it as well', () async {
    await push.mirrorAccount('puremedia', '');
    expect(calls.single.method, 'clearAccount');
  });

  test('no organization, no call', () async {
    await push.mirrorAccount('', 'kelly@kammcs.com-home');
    expect(calls, isEmpty);
  });

  test('a platform without the method is not an error', () async {
    // Android's MainActivity answers MethodNotImplemented; registration must
    // carry on regardless.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushService.channel,
          (call) async => throw MissingPluginException('no such method'),
        );
    await expectLater(
      push.mirrorAccount('puremedia', 'kelly@kammcs.com-home'),
      completes,
    );
  });
}
