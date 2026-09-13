import '../db.dart';

/// The per-person accounting of research/14 §5.2 rules 2 and 6: one
/// notification per person per event, and at most 60 per person per hour per
/// organization. Ids and a timestamp; nothing else is recorded.
abstract interface class SendLedger {
  /// Claims the right to notify [userId] about [eventKey]. False when that
  /// person has already been claimed for this event — a second rule selecting
  /// them, or a replay of the same delivery.
  bool claim({required String org, required String eventKey, required String userId, required DateTime at});

  /// How many notifications this person has had in this org since [since].
  int countSince({required String org, required String userId, required DateTime since});
}

class DbSendLedger implements SendLedger {
  const DbSendLedger(this.db);

  final RelayDb db;

  @override
  bool claim({required String org, required String eventKey, required String userId, required DateTime at}) =>
      db.claimNotificationSend(org: org, eventKey: eventKey, userId: userId, at: at);

  @override
  int countSince({required String org, required String userId, required DateTime since}) =>
      db.notificationSendCount(org: org, userId: userId, since: since);
}

/// The in-memory ledger the engine tests use.
class MemorySendLedger implements SendLedger {
  final Set<String> _claims = {};
  final Map<String, List<DateTime>> _sends = {};

  @override
  bool claim({required String org, required String eventKey, required String userId, required DateTime at}) {
    if (!_claims.add('$org/$eventKey/$userId')) return false;
    (_sends['$org/$userId'] ??= []).add(at);
    return true;
  }

  @override
  int countSince({required String org, required String userId, required DateTime since}) =>
      (_sends['$org/$userId'] ?? const <DateTime>[]).where((at) => !at.isBefore(since)).length;
}
