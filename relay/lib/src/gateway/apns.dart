import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http2/http2.dart';

import '../log.dart';
import 'pointer.dart';

/// Token-based APNs over HTTP/2.
///
/// Apple accepts nothing but h2 on `api.push.apple.com`, and Dart's own
/// `HttpClient` speaks HTTP/1.1 only, so this talks to the `http2` package's
/// [ClientTransportConnection] directly.
///
/// Authentication is the `.p8` authentication key (one key, every app of the
/// team) signed as an ES256 JWT. Apple rejects a JWT younger than an hour if it
/// is re-minted too often and rejects one older than an hour outright, so the
/// token is cached for 50 minutes.
class ApnsSender implements PushSender {
  ApnsSender({
    required this.keyFile,
    required this.keyId,
    required this.teamId,
    required this.topic,
    this.environment = 'sandbox',
    this.timeout = const Duration(seconds: 15),
  });

  /// Builds the sender from the environment, or a disabled one that explains
  /// itself. `APNS_KEY_ID` is the switch: without it there is no way to sign a
  /// JWT, so APNs stays off and `/healthz` says so.
  factory ApnsSender.fromEnv(String Function(String, String) env) => ApnsSender(
    keyFile: env('APNS_KEY_FILE', '/secrets/apns-authkey.p8'),
    keyId: env('APNS_KEY_ID', ''),
    teamId: env('APNS_TEAM_ID', ''),
    topic: env('APNS_TOPIC', 'com.kammcs.boardhop'),
    environment: env('APNS_ENV', 'sandbox'),
  );

  /// Path to the `.p8`, read at send time and never logged or copied.
  final String keyFile;

  /// The ten-character Key ID from the Apple Developer portal.
  final String keyId;

  /// The Apple team id (73W98CESN9).
  final String teamId;

  /// `apns-topic`: the app's bundle id.
  final String topic;

  /// `sandbox` (`api.sandbox.push.apple.com`, debug builds and the simulator)
  /// or `production` (`api.push.apple.com`, TestFlight and the App Store).
  final String environment;

  final Duration timeout;

  /// The `UNNotificationCategory` the Notification Service Extension is
  /// registered for; without it the extension is never invoked.
  static const category = 'boardhop.pointer';

  static const _jwtLifetime = Duration(minutes: 50);

  String? _jwt;
  DateTime? _jwtMintedAt;
  ClientTransportConnection? _connection;

  String get host => environment == 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';

  @override
  bool get ready => keyId.isNotEmpty && teamId.isNotEmpty && File(keyFile).existsSync();

  @override
  String get status {
    if (keyId.isEmpty) return 'disabled (no key id)';
    if (teamId.isEmpty) return 'disabled (no team id)';
    if (!File(keyFile).existsSync()) return 'disabled (no key file)';
    return 'ready ($environment)';
  }

  @override
  Future<PushResult> send(String deviceToken, PushPointer pointer) async {
    if (!ready) return PushResult(PushOutcome.skipped, error: status);
    try {
      final body = utf8.encode(jsonEncode(payload(pointer)));
      final connection = await _connect();
      final stream = connection.makeRequest([
        Header.ascii(':method', 'POST'),
        Header.ascii(':scheme', 'https'),
        Header.ascii(':authority', host),
        Header.ascii(':path', '/3/device/$deviceToken'),
        Header.ascii('authorization', 'bearer ${_authToken()}'),
        Header.ascii('apns-topic', topic),
        Header.ascii('apns-push-type', 'alert'),
        Header.ascii('apns-priority', '10'),
        Header.ascii('apns-collapse-id', pointer.collapseId),
        Header.ascii('content-type', 'application/json'),
        Header.ascii('content-length', '${body.length}'),
      ], endStream: false);
      stream.outgoingMessages.add(DataStreamMessage(body, endStream: true));
      await stream.outgoingMessages.close();

      var status = 0;
      String? apnsId;
      final chunks = <int>[];
      await for (final message in stream.incomingMessages.timeout(timeout)) {
        if (message is HeadersStreamMessage) {
          for (final header in message.headers) {
            final name = ascii.decode(header.name);
            final value = ascii.decode(header.value);
            if (name == ':status') status = int.tryParse(value) ?? 0;
            if (name == 'apns-id') apnsId = value;
          }
        } else if (message is DataStreamMessage) {
          chunks.addAll(message.bytes);
        }
      }

      if (status == 200) return PushResult(PushOutcome.sent, status: status, id: apnsId);

      final reason = _reasonOf(chunks);
      // 410 Gone, or 400 BadDeviceToken / DeviceTokenNotForTopic: the install
      // is finished with this token and the row goes.
      final dead = status == 410 || reason == 'BadDeviceToken' || reason == 'Unregistered';
      return PushResult(dead ? PushOutcome.dead : PushOutcome.failed, status: status, id: apnsId, error: reason);
    } catch (e) {
      // A broken connection must not be reused.
      await _dropConnection();
      return PushResult(PushOutcome.failed, error: '$e');
    }
  }

  /// The APNs payload (research/14 §3.3). Pure function, so the shape is
  /// testable without a key.
  ///
  /// - `mutable-content: 1` wakes the Notification Service Extension, which is
  ///   what enriches the line with the user's own token (R2.7);
  /// - `thread-id` and the `apns-collapse-id` header are both the collapse key,
  ///   so replies stack under one header and a repeat replaces its predecessor;
  /// - `interruption-level: active` for **everything**, approvals included
  ///   (decision D6: no time-sensitive entitlement in the beta);
  /// - the `category` is what makes the extension run for every pointer;
  /// - the pointer's `data` map sits at the **top level**, beside `aps`, which
  ///   is where both the extension and `didReceiveRemoteNotification` read it.
  ///
  /// The alert carries the fallback lines and nothing else: no comment
  /// preview, no build log, no approval instructions.
  Map<String, Object?> payload(PushPointer pointer) {
    final subtitle = pointer.notificationSubtitle;
    return {
      'aps': {
        'alert': {
          'title': pointer.notificationTitle,
          if (subtitle != null) 'subtitle': subtitle,
          'body': pointer.notificationBody,
        },
        'sound': 'default',
        'thread-id': pointer.collapseId,
        'mutable-content': 1,
        'interruption-level': 'active',
        'category': category,
      },
      ...pointer.toData(),
    };
  }

  /// The ES256 JWT Apple wants, re-minted every 50 minutes.
  String _authToken() {
    final minted = _jwtMintedAt;
    final cached = _jwt;
    if (cached != null && minted != null && DateTime.now().difference(minted) < _jwtLifetime) {
      return cached;
    }
    final pem = File(keyFile).readAsStringSync();
    final jwt = JWT(<String, dynamic>{}, issuer: teamId, header: <String, dynamic>{'kid': keyId});
    final signed = jwt.sign(ECPrivateKey(pem), algorithm: JWTAlgorithm.ES256);
    _jwt = signed;
    _jwtMintedAt = DateTime.now();
    logEvent('apns token minted', fields: {'keyId': keyId, 'env': environment});
    return signed;
  }

  /// Apple asks that the connection be kept open rather than re-dialled per
  /// push; it is re-created whenever it has gone away.
  Future<ClientTransportConnection> _connect() async {
    final existing = _connection;
    if (existing != null && existing.isOpen) return existing;
    final socket = await SecureSocket.connect(host, 443, supportedProtocols: ['h2'], timeout: timeout);
    final connection = ClientTransportConnection.viaSocket(socket);
    _connection = connection;
    return connection;
  }

  Future<void> _dropConnection() async {
    final connection = _connection;
    _connection = null;
    try {
      await connection?.finish();
    } catch (_) {
      // Already gone.
    }
  }

  static String? _reasonOf(List<int> body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map && decoded['reason'] is String) return decoded['reason'] as String;
    } catch (_) {
      // Not JSON; say nothing rather than echo bytes into the log.
    }
    return null;
  }

  @override
  Future<void> close() => _dropConnection();
}
