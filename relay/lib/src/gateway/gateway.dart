import '../db.dart';
import '../log.dart';
import 'apns.dart';
import 'fcm.dart';
import 'pointer.dart';

/// The push gateway: the only place in the relay that talks to Apple or
/// Google, and the only place a device token is used.
///
/// It takes a [PushPointer] and a list of [DeviceRow]s, picks the transport by
/// platform, writes one structured log line per send, and deletes the rows the
/// transport declared dead.
class PushGateway {
  PushGateway({required this.apns, required this.fcm, this.db});

  factory PushGateway.fromEnv(String Function(String, String) env, {RelayDb? db}) =>
      PushGateway(apns: ApnsSender.fromEnv(env), fcm: FcmSender.fromEnv(env), db: db);

  final PushSender apns;
  final PushSender fcm;

  /// Where dead devices are removed. Null in tests that only want results.
  final RelayDb? db;

  Map<String, String> get health => {'apns': apns.status, 'fcm': fcm.status};

  /// See [FcmSender.selfTest]; a no-op for a transport that is not FCM.
  Future<Map<String, Object?>> fcmSelfTest() async {
    final sender = fcm;
    if (sender is FcmSender) return sender.selfTest();
    return {'ok': sender.ready, 'status': sender.status};
  }

  /// Sends one pointer to every device given. Returns the results in order.
  Future<List<PushResult>> send(List<DeviceRow> devices, PushPointer pointer) async {
    final results = <PushResult>[];
    for (final device in devices) {
      final sender = device.isAndroid ? fcm : apns;
      final result = await sender.send(device.token, pointer);
      logEvent(
        'push',
        level: result.outcome == PushOutcome.failed ? 'error' : 'info',
        fields: {
          'platform': device.platform,
          'org': device.org,
          'deviceId': device.id,
          // Never the token: the last six characters are enough to line a
          // send up with a device row while supporting someone.
          'token': '…${device.tokenTail}',
          'artifact': '${pointer.artifactType.name}/${pointer.artifactId}',
          'eventType': pointer.eventType,
          'outcome': result.outcome.name,
          'status': result.status,
          'pushId': result.id,
          'error': result.error,
        },
      );
      if (result.outcome == PushOutcome.dead) {
        final removed = db?.deleteByToken(device.token) ?? 0;
        if (removed > 0) {
          logEvent('device removed', fields: {'reason': result.error ?? 'dead token', 'rows': removed});
        }
      }
      results.add(result);
    }
    return results;
  }

  Future<void> close() async {
    await apns.close();
    await fcm.close();
  }
}
