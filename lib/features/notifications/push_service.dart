import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_pointer.dart';

/// The platform half of push: getting this install's device token and turning
/// what the OS hands back into [PushPointer]s.
///
/// **Android** goes through FCM (`firebase_messaging`, configured by
/// `android/app/google-services.json`), and the token arrives the long way
/// round (all three steps were needed to get one at all; see research/06 R1):
///
/// 1. `AndroidManifest.xml` opts the app into FCM's Firebase-Installations
///    registration, because the legacy path answers "FCM Registration failed!"
///    on current Play services. Under that flag the SDK refuses `getToken()`
///    and wants `register()`, which the Flutter plugin does not expose — hence
///    the `com.kammcs.boardhop/push` channel into `MainActivity`.
/// 2. Firebase auto-init is off in the manifest, so nothing registers until
///    the user turns notifications on, and so the SDK cannot emit its one
///    `onNewToken` before a Dart listener exists.
/// 3. `register()` reports the token only through `onTokenRefresh`, once. It is
///    written to shared preferences here, because later launches get no repeat.
///
/// **iOS** does not: there is no Firebase iOS app and no `GoogleService-Info`.
/// The Runner registers for remote notifications itself and hands the APNs
/// token over the `com.kammcs.boardhop/push` method channel, so the only
/// credential in play is the team's APNs key on the relay.
///
/// Nothing here routes or shows anything; `PushCoordinator` does that, because
/// only it knows which signed-in account an organization belongs to.
class PushService {
  PushService._();

  static const channel = MethodChannel('com.kammcs.boardhop/push');

  /// Builds the service and starts listening. Safe to call on a platform with
  /// no push at all (tests, desktop): it simply never produces a token.
  static Future<PushService> create() async {
    final service = PushService._();
    try {
      service._prefs = await SharedPreferences.getInstance();
    } catch (_) {
      service._prefs = null;
    }
    await service._init();
    return service;
  }

  /// Where the last token is remembered; the platform hands one over once.
  static const tokenPrefKey = 'push.deviceToken';

  /// For tests: nothing platform-specific behind it.
  @visibleForTesting
  PushService.fake();

  /// This install's APNs or FCM token, null until the OS gives one. Rotations
  /// arrive here too, and the coordinator re-registers.
  final ValueNotifier<String?> token = ValueNotifier<String?>(null);

  SharedPreferences? _prefs;
  final _foreground = StreamController<PushPointer>.broadcast();
  final _opened = StreamController<PushPointer>.broadcast();
  PushPointer? _launchPointer;

  /// Pushes that arrived while the app was in front; nothing is shown for them
  /// by the OS, so the coordinator posts a local notification instead.
  Stream<PushPointer> get foreground => _foreground.stream;

  /// A notification the user tapped while the app was running.
  Stream<PushPointer> get opened => _opened.stream;

  /// `android` or `ios`; what the relay stores. Null where push does not
  /// exist.
  String? get platform {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  /// The notification that launched the app from cold, once.
  PushPointer? takeLaunchPointer() {
    final pointer = _launchPointer;
    _launchPointer = null;
    return pointer;
  }

  Future<void> _init() async {
    try {
      if (platform == 'android') {
        await _initAndroid();
      } else if (platform == 'ios') {
        await _initIos();
      }
    } catch (e) {
      // Push is a bonus: a Firebase or channel failure must never stop the app
      // from starting.
      debugPrint('Push unavailable: $e');
    }
  }

  Future<void> _initAndroid() async {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;

    // MainActivity forwards every onNewToken here, including one minted before
    // this listener existed.
    channel.setMethodCallHandler(_onPlatformCall);

    FirebaseMessaging.onMessage.listen((message) {
      final pointer = PushPointer.tryFrom(message.data);
      if (pointer != null) _foreground.add(pointer);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final pointer = PushPointer.tryFrom(message.data);
      if (pointer != null) _opened.add(pointer);
    });
    messaging.onTokenRefresh.listen(_storeToken);

    final initial = await messaging.getInitialMessage();
    if (initial != null) _launchPointer = PushPointer.tryFrom(initial.data);

    // Whatever was learned on an earlier run. Registration itself waits for
    // the user's opt-in: see [refreshToken].
    final remembered = _prefs?.getString(tokenPrefKey);
    if (remembered != null && remembered.isNotEmpty) token.value = remembered;
  }

  /// Turns FCM on for this install and waits for the one `onTokenRefresh` the
  /// SDK emits. Called when the user has notifications on, never before.
  Future<String?> _androidRegister() async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await channel.invokeMethod<void>('register');
      final value = await _awaitToken(const Duration(seconds: 30));
      if (value != null) return value;
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
    // An install where the Installations registration is not in force still
    // answers getToken().
    try {
      final value = await FirebaseMessaging.instance.getToken();
      if (value != null) _storeToken(value);
      return value;
    } catch (e) {
      debugPrint('Push token unavailable: $e');
      return null;
    }
  }

  void _storeToken(String value) {
    token.value = value;
    _prefs?.setString(tokenPrefKey, value);
  }

  /// Waits for [token] to hold something, up to [limit].
  Future<String?> _awaitToken(Duration limit) {
    if (token.value != null) return Future.value(token.value);
    final completer = Completer<String?>();
    void listener() {
      if (token.value != null && !completer.isCompleted) {
        completer.complete(token.value);
      }
    }

    token.addListener(listener);
    return completer.future
        .timeout(limit, onTimeout: () => null)
        .whenComplete(() => token.removeListener(listener));
  }

  /// The iOS side is **unverified**: it has never been built or run (no Mac in
  /// the R1 session, and APNs is off until the key id exists). See research/06.
  Future<void> _initIos() async {
    channel.setMethodCallHandler(_onPlatformCall);
    final existing = await channel.invokeMethod<String>('register');
    if (existing != null && existing.isNotEmpty) _storeToken(existing);
  }

  /// What the Runner (iOS) and MainActivity (Android) call into.
  Future<Object?> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        final value = call.arguments;
        if (value is String && value.isNotEmpty) _storeToken(value);
      case 'onMessage':
        final pointer = _pointerOf(call.arguments);
        if (pointer != null) _foreground.add(pointer);
      case 'onOpened':
        final pointer = _pointerOf(call.arguments);
        if (pointer != null) _opened.add(pointer);
    }
    return null;
  }

  static PushPointer? _pointerOf(Object? arguments) {
    if (arguments is! Map) return null;
    return PushPointer.tryFrom({
      for (final entry in arguments.entries) '${entry.key}': entry.value,
    });
  }

  /// Asks the platform for a token again, for the "Turn on" flow: on Android
  /// `getToken` only answers once notifications are permitted.
  Future<String?> refreshToken() async {
    try {
      // Always, even with a remembered token: this is where FCM is switched
      // on for the install, and the switch does not survive a restart.
      if (platform == 'android') return await _androidRegister();
      if (platform == 'ios') {
        final value = await channel.invokeMethod<String>('register');
        if (value != null && value.isNotEmpty) token.value = value;
        return token.value;
      }
    } catch (e) {
      debugPrint('Push token unavailable: $e');
    }
    return token.value;
  }

  /// Drops this install's token so a signed-out phone stops being wakeable
  /// even if the relay row outlives the sign-out.
  Future<void> deleteToken() async {
    try {
      // `unregister()`, not `deleteToken()`: the same flag that disables
      // `getToken()` disables its twin.
      if (platform == 'android') {
        await channel.invokeMethod<void>('unregister');
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
      }
    } catch (e) {
      debugPrint('Push token delete failed: $e');
    }
    token.value = null;
    await _prefs?.remove(tokenPrefKey);
  }

  void dispose() {
    _foreground.close();
    _opened.close();
    token.dispose();
  }
}
