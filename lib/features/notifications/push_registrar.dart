import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the relay lives for one organization.
///
/// R1 answers with the shared kammcs instance for every org. When the
/// Marketplace extension lands, this reads the relay URL out of the org's
/// extension data store (research/06, "Marketplace extension"), which is why
/// every caller goes through this one function.
String relayUrlFor(String org) => 'https://boardhop.relay.kammcs.com';

/// One HTTP round trip to the relay, injected so tests need no network.
typedef RelayCall = Future<RelayResponse> Function(
  String method,
  Uri url, {
  String? bearer,
  Map<String, Object?>? body,
});

/// Mirrors the MSAL account identifier that registered one organization into a
/// platform store the app itself does not own — on iOS the app group the
/// Notification Service Extension reads (R2.7). Null clears it.
///
/// Injected so the registrar stays testable and so nothing is called on a
/// platform that has no such store; `PushService.mirrorAccount` is the live one.
typedef PushAccountMirror = Future<void> Function(
  String org,
  String? accountId,
);

class RelayResponse {
  const RelayResponse(this.statusCode, [this.body = const {}]);

  final int statusCode;
  final Map<String, Object?> body;

  bool get ok => statusCode >= 200 && statusCode < 300;
  bool get unauthorized => statusCode == 401;
}

/// What the app remembers about a successful registration. Per account and
/// organization, in shared preferences.
@immutable
class PushRegistration {
  const PushRegistration({
    required this.deviceId,
    required this.org,
    required this.platform,
    required this.registeredAt,
    required this.lastHeartbeatAt,
  });

  factory PushRegistration.fromJson(Map<String, Object?> json) =>
      PushRegistration(
        deviceId: json['deviceId'] as String? ?? '',
        org: json['org'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        registeredAt:
            DateTime.tryParse(json['registeredAt'] as String? ?? '') ??
            DateTime.now(),
        lastHeartbeatAt:
            DateTime.tryParse(json['lastHeartbeatAt'] as String? ?? '') ??
            DateTime.now(),
      );

  final String deviceId;
  final String org;
  final String platform;
  final DateTime registeredAt;
  final DateTime lastHeartbeatAt;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'org': org,
    'platform': platform,
    'registeredAt': registeredAt.toIso8601String(),
    'lastHeartbeatAt': lastHeartbeatAt.toIso8601String(),
  };

  PushRegistration copyWith({DateTime? lastHeartbeatAt}) => PushRegistration(
    deviceId: deviceId,
    org: org,
    platform: platform,
    registeredAt: registeredAt,
    lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
  );
}

/// Registers this install's APNs/FCM token with the relay for one signed-in
/// account, keeps the registration alive with a daily heartbeat, and removes
/// it on sign-out.
///
/// The Azure DevOps access token is sent once per call as the bearer so the
/// relay can confirm who the caller is in that organization; the relay stores
/// ids only (research/06). Nothing here is logged.
class PushRegistrar {
  PushRegistrar({
    required this.accountId,
    required this.accessToken,
    RelayCall? call,
    this.prefs,
    String Function(String org)? relayUrl,
    this.mirrorAccount,
    this.appVersion = defaultAppVersion,
  }) : _call = call ?? dioRelayCall(),
       _relayUrl = relayUrl ?? relayUrlFor;

  /// Bumped with pubspec's `version`; `--dart-define BOARDHOP_VERSION` wins so
  /// a TestFlight or Play build can report its build number.
  static const defaultAppVersion = String.fromEnvironment(
    'BOARDHOP_VERSION',
    defaultValue: '1.0.0',
  );

  /// Heartbeat at most this often.
  static const heartbeatEvery = Duration(days: 1);

  final String accountId;

  /// The account's Azure DevOps access token, fetched fresh per call.
  final Future<String> Function() accessToken;

  final RelayCall _call;
  final String Function(String org) _relayUrl;

  /// iOS: the second copy of [msalAccountKeyFor], in the app group. Null on
  /// Android, where the messaging service reads shared preferences itself.
  final PushAccountMirror? mirrorAccount;

  final String appVersion;

  /// Injected in tests (`SharedPreferences.setMockInitialValues` gives one);
  /// otherwise resolved on first use.
  SharedPreferences? prefs;

  /// Listen to rebuild the Settings row.
  final ValueNotifier<PushRegistration?> registration =
      ValueNotifier<PushRegistration?>(null);

  String get _prefKey => 'push.registration.$accountId';

  /// Where the Android messaging service looks up which signed-in account to
  /// ask MSAL for a token as, when a push for [org] arrives and the app is not
  /// running (R2.6, research/14 §4.1 "Token").
  ///
  /// [accountId] is the MSAL account identifier — the same string
  /// `AuthService.acquireSilent` passes as `identifier` — so Kotlin's
  /// `IMultipleAccountPublicClientApplication.getAccount` takes it as it is.
  /// `shared_preferences` prefixes its Android keys with `flutter.`, so the
  /// service reads `flutter.push.msal.account.{org}` out of
  /// `FlutterSharedPreferences`. Nothing secret is stored: an account
  /// identifier, not a token.
  static String msalAccountKeyFor(String org) => 'push.msal.account.$org';

  Future<SharedPreferences?> _preferences() async {
    final existing = prefs;
    if (existing != null) return existing;
    try {
      return prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Reads what was stored for this account, and publishes it on
  /// [registration].
  Future<PushRegistration?> load() async {
    final store = await _preferences();
    final raw = store?.getString(_prefKey);
    if (raw == null) return registration.value = null;
    try {
      final value = PushRegistration.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
      // Also on load, so a device that registered before R2.6 tells the
      // messaging service which account to ask MSAL for without having to
      // register again.
      if (value.org.isNotEmpty) {
        await store?.setString(msalAccountKeyFor(value.org), accountId);
        await mirrorAccount?.call(value.org, accountId);
      }
      return registration.value = value;
    } catch (_) {
      return registration.value = null;
    }
  }

  Future<void> _store(PushRegistration? value) async {
    final previous = registration.value;
    registration.value = value;
    final store = await _preferences();
    if (value == null) {
      await store?.remove(_prefKey);
      final org = previous?.org;
      if (org != null && org.isNotEmpty) {
        await store?.remove(msalAccountKeyFor(org));
        await mirrorAccount?.call(org, null);
      }
    } else {
      await store?.setString(_prefKey, jsonEncode(value.toJson()));
      // The Android messaging service needs this to acquire a token silently
      // for a push that arrives while the app is not running; the iOS
      // extension needs the same value in the app group (R2.7).
      await store?.setString(msalAccountKeyFor(value.org), accountId);
      await mirrorAccount?.call(value.org, accountId);
    }
  }

  /// `POST /v1/devices`. Idempotent on the relay side, so calling it again
  /// after a token rotation is the right move.
  ///
  /// Returns null when the relay refused; a 401 means the token was not good
  /// for that org, and the stored registration is dropped so the next start,
  /// with a refreshed token, registers again.
  Future<PushRegistration?> register({
    required String org,
    required String platform,
    required String token,
  }) async {
    final response = await _send('POST', _relayUrl(org), '/v1/devices', {
      'org': org,
      'platform': platform,
      'token': token,
      'appVersion': appVersion,
      'locale': locale,
      'tzOffsetMinutes': tzOffsetMinutes,
    });
    if (response == null) return null;
    if (response.unauthorized) {
      await _store(null);
      return null;
    }
    if (!response.ok) return null;
    final deviceId = response.body['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) return null;
    final now = DateTime.now();
    final value = PushRegistration(
      deviceId: deviceId,
      org: org,
      platform: platform,
      registeredAt: now,
      lastHeartbeatAt: now,
    );
    await _store(value);
    return value;
  }

  /// Once a day at app start: move `lastSeenAt` on the relay and hand over a
  /// rotated token. A 404 or 401 drops the local registration so the caller
  /// registers from scratch.
  Future<void> heartbeat({required String token, DateTime? now}) async {
    final current = registration.value ?? await load();
    if (current == null) return;
    final at = now ?? DateTime.now();
    if (at.difference(current.lastHeartbeatAt) < heartbeatEvery) return;

    final response = await _send(
      'POST',
      _relayUrl(current.org),
      '/v1/devices/${current.deviceId}/heartbeat',
      {
        'token': token,
        'appVersion': appVersion,
        'locale': locale,
        'tzOffsetMinutes': tzOffsetMinutes,
      },
    );
    if (response == null) return;
    if (response.unauthorized || response.statusCode == 404) {
      await _store(null);
      return;
    }
    if (response.ok) await _store(current.copyWith(lastHeartbeatAt: at));
  }

  /// `DELETE /v1/devices/{id}` on sign-out. The local record goes either way:
  /// a device the relay could not be told about is cleaned up there when its
  /// token stops working.
  Future<void> unregister() async {
    final current = registration.value ?? await load();
    if (current == null) return;
    await _send(
      'DELETE',
      _relayUrl(current.org),
      '/v1/devices/${current.deviceId}',
      null,
    );
    await _store(null);
  }

  /// `POST /v1/test-push`: the relay pushes a fixed pointer to every device
  /// this identity has registered in that org. Returns how many were sent, or
  /// null when the call failed.
  Future<int?> sendTestPush({required String org}) async {
    final response = await _send('POST', _relayUrl(org), '/v1/test-push', {
      'org': org,
    });
    if (response == null || !response.ok) return null;
    final sent = response.body['sent'];
    return sent is int ? sent : 0;
  }

  Future<RelayResponse?> _send(
    String method,
    String base,
    String path,
    Map<String, Object?>? body,
  ) async {
    String bearer;
    try {
      bearer = await accessToken();
    } catch (e) {
      debugPrint('Push: no access token ($e)');
      return null;
    }
    try {
      return await _call(
        method,
        Uri.parse('$base$path'),
        bearer: bearer,
        body: body,
      );
    } catch (e) {
      debugPrint('Push: relay call failed ($e)');
      return null;
    }
  }

  /// Minutes east of UTC, sent on registration and with every heartbeat: it
  /// is the only thing that makes the relay's quiet hours this device's local
  /// time rather than UTC (research/14 §6, relay README "Device registration").
  static int get tzOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// `en_GB`; the relay stores it so a future digest can be localised.
  static String get locale {
    try {
      return Platform.localeName;
    } catch (_) {
      return 'und';
    }
  }

  void dispose() => registration.dispose();
}

/// The production [RelayCall], over the app's existing HTTP client.
RelayCall dioRelayCall({Dio? dio}) {
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Every status is a result; the caller decides what it means.
          validateStatus: (_) => true,
        ),
      );
  return (method, url, {String? bearer, Map<String, Object?>? body}) async {
    final response = await client.requestUri<Object?>(
      url,
      data: body,
      options: Options(
        method: method,
        headers: {
          if (bearer != null) 'Authorization': 'Bearer $bearer',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    return RelayResponse(
      response.statusCode ?? 0,
      data is Map<String, Object?> ? data : const {},
    );
  };
}
