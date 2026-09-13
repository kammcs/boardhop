import 'dart:async';

import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:boardhop_relay/src/hooks/hook_event.dart';
import 'package:boardhop_relay/src/identity.dart';
import 'package:boardhop_relay/src/log.dart';

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
