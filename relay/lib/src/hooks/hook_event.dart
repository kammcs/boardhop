import '../log.dart';
import 'hook_kind.dart';
import 'routing_view.dart';

/// One accepted service-hook delivery, as it is handed to the queue.
///
/// It carries the [RoutingView] and nothing else: the raw body is decoded,
/// projected and dropped inside the request handler, so there is no reference
/// to it anywhere past this point.
class HookEvent {
  HookEvent({required this.view, DateTime? receivedAt}) : receivedAt = receivedAt ?? DateTime.now().toUtc();

  final RoutingView view;
  final DateTime receivedAt;

  String get org => view.org;
  HookKind get kind => view.kind;
  String? get subId => view.subId;
  String? get activityId => view.activityId;

  @override
  String toString() => 'HookEvent(${view.kind.label} ${view.artifactId ?? '-'})';
}

/// What the queue's single consumer calls. R2.2 replaces the logging
/// implementation with the audience rule engine.
abstract interface class HookProcessor {
  Future<void> process(HookEvent event);
}

/// R2.1's only processor: one `hook routed` line per event, ids and counts only.
class LoggingHookProcessor implements HookProcessor {
  const LoggingHookProcessor();

  @override
  Future<void> process(HookEvent event) async {
    logEvent(
      'hook routed',
      fields: {
        ...event.view.toLogFields(),
        'lagMs': DateTime.now().toUtc().difference(event.receivedAt).inMilliseconds,
      },
    );
  }
}
