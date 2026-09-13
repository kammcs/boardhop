import 'dart:collection';

import '../log.dart';
import 'hook_event.dart';

/// The in-process hand-off that lets `POST /hooks/{org}` answer 200 in
/// milliseconds (research/14 §5.2 rule 4: Azure DevOps retries anything that is
/// not answered quickly, and every retry is a duplicate to dedup).
///
/// Bounded and single-consumer: work is done one event at a time, in arrival
/// order, and an overflow is dropped and counted rather than queued without
/// limit. Nothing here touches the network — the processor does.
class HookQueue {
  HookQueue({required this.processor, this.capacity = 1000});

  final HookProcessor processor;

  /// How many events may wait. Beyond it, [add] drops and counts.
  final int capacity;

  final Queue<HookEvent> _pending = Queue<HookEvent>();
  Future<void>? _worker;
  var _dropped = 0;
  var _processed = 0;
  var _failed = 0;
  var _closed = false;

  /// Events dropped because the queue was full, since start.
  int get dropped => _dropped;

  /// Events the processor has finished with, since start.
  int get processed => _processed;

  /// Events whose processing threw. They are counted, logged and forgotten.
  int get failed => _failed;

  /// How many events are waiting (the one in flight is not among them).
  int get depth => _pending.length;

  bool get isIdle => _pending.isEmpty && _worker == null;

  /// Queues [event]. Returns false when the queue was full, which is a drop:
  /// the caller still answers 200, because a 5xx would only bring the same
  /// delivery back again.
  bool add(HookEvent event) {
    if (_closed) return false;
    if (_pending.length >= capacity) {
      _dropped++;
      logEvent(
        'hook dropped',
        level: 'warn',
        fields: {'org': event.org, 'kind': event.kind.label, 'reason': 'queue-full', 'dropped': _dropped},
      );
      return false;
    }
    _pending.add(event);
    _worker ??= _run();
    return true;
  }

  Future<void> _run() async {
    while (_pending.isNotEmpty) {
      final event = _pending.removeFirst();
      try {
        await processor.process(event);
        _processed++;
      } catch (e) {
        _failed++;
        logEvent(
          'hook processing failed',
          level: 'error',
          fields: {'org': event.org, 'kind': event.kind.label, 'subId': event.subId, 'error': '$e'},
        );
      }
    }
    _worker = null;
  }

  /// Completes when the queue has drained. Tests use it; the server does not.
  Future<void> drain() async {
    while (_worker != null) {
      await _worker;
    }
  }

  /// Stops accepting and waits for what is already queued.
  Future<void> close() async {
    _closed = true;
    await drain();
  }
}
