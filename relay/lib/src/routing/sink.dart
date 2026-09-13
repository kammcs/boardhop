import '../log.dart';
import 'notification.dart';

/// Where a finished [Notification] goes. R2.2 ships one implementation that
/// writes a log line; R2.3 wires the push gateway behind the same interface,
/// which is the only change the engine needs for real sends.
abstract interface class NotificationSink {
  Future<void> deliver(Notification notification);
}

/// One `notification` line per notification: ids, the kind, the verb and how
/// many people it is for. Never the title, never the actor's name, never the
/// detail — those three exist only inside the in-flight object.
class LoggingNotificationSink implements NotificationSink {
  const LoggingNotificationSink();

  @override
  Future<void> deliver(Notification notification) async => logEvent('notification', fields: notification.toLogFields());
}

/// Collects instead of delivering. Used by `dart test`.
class RecordingNotificationSink implements NotificationSink {
  final List<Notification> notifications = [];

  @override
  Future<void> deliver(Notification notification) async => notifications.add(notification);
}
