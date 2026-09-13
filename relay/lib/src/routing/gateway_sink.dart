import '../db.dart';
import '../gateway/gateway.dart';
import '../gateway/pointer.dart';
import '../log.dart';
import 'notification.dart';
import 'push_pointer_adapter.dart';
import 'sink.dart';

/// The sink that actually pushes (research/14 §9, R2.3): for every identity the
/// rules chose, every device that identity has registered for the org gets the
/// same pointer.
///
/// Somebody with no registered device is simply not reached — the relay keeps
/// no inbox (research/14 §5.2 rule 7) — and the per-send log line, the dead
/// token handling and the 410/UNREGISTERED row deletion all stay where they
/// were, inside [PushGateway].
class GatewayNotificationSink implements NotificationSink {
  GatewayNotificationSink({required this.db, required this.gateway, DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final RelayDb db;
  final PushGateway gateway;
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<void> deliver(Notification notification) async {
    final pointer = pointerFromNotification(notification, sentAt: _clock());

    var users = 0;
    var devices = 0;
    final outcomes = <PushOutcome, int>{};
    for (final userId in notification.recipients) {
      final rows = db.devicesFor(notification.org, userId);
      if (rows.isEmpty) continue;
      users++;
      devices += rows.length;
      // One line per send comes from the gateway itself: platform, the last
      // six characters of the token, outcome, status and the push id.
      for (final result in await gateway.send(rows, pointer)) {
        outcomes[result.outcome] = (outcomes[result.outcome] ?? 0) + 1;
      }
    }

    logEvent(
      'notification',
      fields: {
        ...notification.toLogFields(),
        'reached': users,
        'devices': devices,
        for (final outcome in PushOutcome.values)
          if (outcomes[outcome] != null) outcome.name: outcomes[outcome],
      },
    );
  }
}
