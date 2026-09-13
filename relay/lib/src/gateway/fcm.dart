import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import '../log.dart';
import 'pointer.dart';

/// FCM HTTP v1.
///
/// The legacy server key is gone; v1 wants an OAuth2 access token minted from
/// the Firebase service account. `googleapis_auth` keeps one and refreshes it
/// before it expires, so this class only builds the message.
class FcmSender implements PushSender {
  FcmSender({
    required this.projectId,
    required this.serviceAccountFile,
    this.androidChannelId = 'activity',
    this.timeout = const Duration(seconds: 15),
    this.baseClient,
  });

  factory FcmSender.fromEnv(String Function(String, String) env) => FcmSender(
    projectId: env('FCM_PROJECT_ID', ''),
    serviceAccountFile: env('FCM_SERVICE_ACCOUNT', '/secrets/fcm-service-account.json'),
  );

  static const scope = 'https://www.googleapis.com/auth/firebase.messaging';

  /// `boardhop-d4b8f`.
  final String projectId;

  /// Path to the service-account JSON, mounted read-only at `/secrets`.
  final String serviceAccountFile;

  /// The notification channel the Android app already owns (see
  /// `lib/core/notifications/notification_service.dart`), so a pushed
  /// notification looks exactly like a polled one.
  final String androidChannelId;

  final Duration timeout;

  /// Injected in tests so the OAuth2 exchange can be faked.
  final http.Client Function()? baseClient;

  auth.AutoRefreshingAuthClient? _client;

  String get endpoint => 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

  @override
  bool get ready => projectId.isNotEmpty && File(serviceAccountFile).existsSync();

  @override
  String get status {
    if (projectId.isEmpty) return 'disabled (no project id)';
    if (!File(serviceAccountFile).existsSync()) return 'disabled (no service account)';
    return 'ready';
  }

  @override
  Future<PushResult> send(String deviceToken, PushPointer pointer) async {
    if (!ready) return PushResult(PushOutcome.skipped, error: status);
    try {
      final client = await _authClient();
      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'message': message(deviceToken, pointer)}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final name = _stringAt(response.body, 'name');
        return PushResult(PushOutcome.sent, status: response.statusCode, id: name);
      }

      final code = _errorCode(response.body);
      // UNREGISTERED / NOT_FOUND: the app was uninstalled or the token was
      // replaced. The row goes; the app registers again on next launch.
      final dead = code == 'UNREGISTERED' || code == 'NOT_FOUND' || response.statusCode == 404;
      return PushResult(
        dead ? PushOutcome.dead : PushOutcome.failed,
        status: response.statusCode,
        error: code ?? 'http ${response.statusCode}',
      );
    } catch (e) {
      return PushResult(PushOutcome.failed, error: '$e');
    }
  }

  /// Asks FCM to validate a message without delivering it (`validate_only`),
  /// against a deliberately bogus device token.
  ///
  /// It answers the one question a log line cannot: is the service account
  /// good **and** is the Cloud Messaging API enabled for the project? An
  /// enabled project rejects the bogus token with `INVALID_ARGUMENT`; a
  /// project with the API switched off answers 403 `PERMISSION_DENIED` or
  /// `SERVICE_DISABLED`, and a broken service account never gets that far.
  /// Read it through `GET /v1/admin/fcm-check`.
  Future<Map<String, Object?>> selfTest() async {
    if (!ready) return {'ok': false, 'status': status};
    try {
      final client = await _authClient();
      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'validate_only': true,
              'message': message('fcm-self-test-token-not-a-real-device', _probePointer),
            }),
          )
          .timeout(timeout);
      final code = _errorCode(response.body);
      return {
        // A rejected bogus token is the healthy answer: the call reached FCM,
        // was authenticated, and only the device token was wrong.
        'ok': response.statusCode == 200 || code == 'INVALID_ARGUMENT',
        'httpStatus': response.statusCode,
        'code': code,
        'project': projectId,
      };
    } catch (e) {
      return {'ok': false, 'error': '$e', 'project': projectId};
    }
  }

  static final _probePointer = PushPointer(
    org: 'boardhop',
    eventType: 'boardhop.selftest',
    artifactType: PushArtifactType.build,
    artifactId: '0',
    project: '',
  );

  /// The v1 `message` object. Pure function, so the shape is testable without
  /// a service account.
  Map<String, Object?> message(String deviceToken, PushPointer pointer) => {
    'token': deviceToken,
    'notification': {'title': pointer.notificationTitle, 'body': pointer.notificationBody},
    'data': pointer.toData(),
    'android': {
      'priority': 'high',
      'collapse_key': pointer.collapseId,
      'notification': {'channel_id': androidChannelId, 'tag': pointer.collapseId},
    },
  };

  Future<auth.AutoRefreshingAuthClient> _authClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final json = jsonDecode(File(serviceAccountFile).readAsStringSync());
    final credentials = auth.ServiceAccountCredentials.fromJson(json);
    final created = await auth.clientViaServiceAccount(credentials, const [scope], baseClient: baseClient?.call());
    logEvent('fcm service account loaded', fields: {'project': projectId});
    return _client = created;
  }

  static String? _stringAt(String body, String key) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded[key] is String) return decoded[key] as String;
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  /// `error.details[].errorCode` (FCM's own code) or `error.status`.
  static String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is! Map) return null;
      final details = error['details'];
      if (details is List) {
        for (final detail in details) {
          if (detail is Map && detail['errorCode'] is String) return detail['errorCode'] as String;
        }
      }
      if (error['status'] is String) return error['status'] as String;
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  @override
  Future<void> close() async {
    _client?.close();
    _client = null;
  }
}
