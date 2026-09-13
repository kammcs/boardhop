import 'dart:async';

import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:boardhop_relay/src/hooks/hook_event.dart';
import 'package:boardhop_relay/src/hooks/routing_view.dart';
import 'package:boardhop_relay/src/identity.dart';
import 'package:boardhop_relay/src/log.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/notification.dart';
import 'package:boardhop_relay/src/routing/prefs.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/routing/rule_engine.dart';
import 'package:boardhop_relay/src/routing/send_ledger.dart';
import 'package:boardhop_relay/src/routing/sink.dart';
import 'package:boardhop_relay/src/verb.dart';

/// A push transport that records instead of dialling Apple or Google.
class FakeSender implements PushSender {
  FakeSender({this.ready = true, this.result = const PushResult(PushOutcome.sent, status: 200, id: 'fake-id')});

  @override
  final bool ready;

  /// What every send answers.
  PushResult result;

  final List<({String token, PushPointer pointer})> sent = [];

  @override
  String get status => ready ? 'ready (fake)' : 'disabled (fake)';

  @override
  Future<PushResult> send(String deviceToken, PushPointer pointer) async {
    sent.add((token: deviceToken, pointer: pointer));
    return result;
  }

  @override
  Future<void> close() async {}
}

/// A hook processor that records instead of routing. Set [gate] to hold the
/// single consumer inside `process`, so the queue can be filled up on purpose.
class RecordingHookProcessor implements HookProcessor {
  final List<HookEvent> events = [];
  Completer<void>? gate;

  @override
  Future<void> process(HookEvent event) async {
    final held = gate;
    if (held != null) await held.future;
    events.add(event);
  }
}

/// Collects every JSON log line written while [body] runs. The relay logs
/// through one function, so this sees request lines and events alike.
Future<List<String>> captureLog(Future<void> Function() body) async {
  final lines = <String>[];
  logWriter = lines.add;
  try {
    await body();
  } finally {
    logWriter = null;
  }
  return lines;
}

/// An identity validator driven by a map of `bearer -> user id`. Any org the
/// token is not listed for answers null, so the "wrong org" path is testable.
IdentityValidator fakeValidator(Map<String, String> usersByToken, {Set<String>? orgs}) {
  return (String org, String bearer) async {
    if (orgs != null && !orgs.contains(org)) return null;
    final id = usersByToken[bearer];
    if (id == null) return null;
    return AdoIdentity(id: id, descriptor: 'aad.$id');
  };
}

/// A preferences source that hands the same [UserPrefs] to everybody, with an
/// optional per-person time zone. R2.3 replaces the production one with a
/// table; the engine only ever sees this interface.
class FixedPrefsSource implements PrefsSource {
  FixedPrefsSource(this.prefs, {this.tzOffsetMinutes});

  final UserPrefs prefs;
  final int? tzOffsetMinutes;

  @override
  UserPrefs prefsFor(String org, String userId) => prefs;

  @override
  int? timeZoneOffsetMinutes(String org, String userId) => tzOffsetMinutes;
}

/// Preferences that say yes to everything: the way to test a rule without the
/// §6 defaults hiding half of it.
class AllOnPrefs implements UserPrefs {
  const AllOnPrefs();

  @override
  bool allows(Verb verb, {required CandidateReason reason, String? detail, String? artifactKey}) => true;

  @override
  bool quietHoursSuppress(Verb verb, DateTime nowUtc, int? tzOffsetMinutes) => false;
}

/// Quiet hours that cover the whole day, to prove what they do and do not
/// stop. This is the **real** [StoredPrefs] with an all-day window (start ==
/// end), so the approval exemption under test is the shipped one.
class AlwaysQuietPrefs extends StoredPrefs {
  const AlwaysQuietPrefs()
    : super(
        const PushPrefs(
          quietHours: QuietHours(enabled: true, start: '00:00', end: '00:00'),
        ),
      );
}

/// The rule engine with in-memory state, ledger and sink — everything the
/// tests need and nothing that touches a disk or a socket.
class RoutingHarness {
  RoutingHarness({
    UserPrefs prefs = const DefaultPrefs(),
    DateTime? now,
    int? tzOffsetMinutes,
    int? maxFanOut,
    int? maxPerUserPerHour,
  }) : state = MemoryRoutingState(),
       sink = RecordingNotificationSink(),
       sends = MemorySendLedger() {
    engine = RuleEngine(
      state: state,
      prefs: FixedPrefsSource(prefs, tzOffsetMinutes: tzOffsetMinutes),
      sink: sink,
      sends: sends,
      maxRecipientsPerEvent: maxFanOut ?? RuleEngine.maxFanOut,
      maxPerUserPerHour: maxPerUserPerHour ?? RuleEngine.maxPerUserHourly,
      clock: () => now ?? DateTime.now().toUtc(),
    );
  }

  final MemoryRoutingState state;
  final RecordingNotificationSink sink;
  final MemorySendLedger sends;
  late final RuleEngine engine;

  /// Processes one view and returns only the notifications it produced.
  Future<List<Notification>> run(RoutingView view) async {
    final before = sink.notifications.length;
    await engine.process(HookEvent(view: view));
    return sink.notifications.sublist(before);
  }

  /// Every identity the notifications of one run reached.
  Set<String> recipientsOf(List<Notification> notifications) => {
    for (final notification in notifications) ...notification.recipients,
  };
}
