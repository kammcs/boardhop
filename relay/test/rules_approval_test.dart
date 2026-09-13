import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/routing/approval_rules.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';

/// research/14 §2.4 and §1.4. The requester of a run reaches the relay only
/// through `run-state-changed`; the approval events name them by display name.
void main() {
  late MemoryRoutingState state;

  setUp(() => state = MemoryRoutingState());

  List<Candidate> evaluate(HookKind kind, Map<String, Object?> body) =>
      kind.isApproval ? evaluateApproval(viewOf(kind, body), state) : evaluatePipelineState(viewOf(kind, body), state);

  /// Bob requested the run in every fixture; Ada is the default approver.
  void queueTheRun() => evaluate(HookKind.runState, runStateChanged(subId: 'sub', state: 'inProgress'));

  group('run-state-changed', () {
    test('notifies nobody and records the requester as an identity', () {
      expect(evaluate(HookKind.runState, runStateChanged(subId: 'sub')), isEmpty);
      final row = state.run(fixtureOrg, '20163')!;
      expect(row.requestedForId, bobId);
      expect(row.requestedById, adaId);
      expect(row.pipelineId, '139');
    });

    test('stage-state-changed notifies nobody and records nothing', () {
      expect(evaluate(HookKind.stageState, stageStateChanged(subId: 'sub')), isEmpty);
      expect(state.runs, isEmpty);
    });

    test('the approval payload itself names no requester id', () {
      final view = viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub'));
      expect(view.requestedForId, isNull, reason: 'run.requestedFor is a display name string (w25)');
    });
  });

  group('approval-pending', () {
    test('every user approver is asked, anchored on the approval', () {
      queueTheRun();
      final candidates = evaluate(
        HookKind.approvalPending,
        approvalEvent(subId: 'sub', approverIds: const [adaId, cleoId]),
      );
      expect(candidates.map((c) => (c.userId, c.verb, c.detail, c.anchor)), [
        (adaId, Verb.approvalPending, 'Deploy', 'approval:44444444-eeee-4eee-8eee-444444444444'),
        (cleoId, Verb.approvalPending, 'Deploy', 'approval:44444444-eeee-4eee-8eee-444444444444'),
      ]);
    });

    test('a group approver is skipped: the beta cannot expand one', () {
      queueTheRun();
      final candidates = evaluate(HookKind.approvalPending, approvalEvent(subId: 'sub', withGroupApprover: true));
      expect(candidates.map((c) => c.userId), [adaId]);
    });

    test("the run's requester is skipped when somebody else can approve", () {
      queueTheRun();
      final candidates = evaluate(
        HookKind.approvalPending,
        approvalEvent(subId: 'sub', approverIds: const [bobId, cleoId]),
      );
      expect(candidates.map((c) => c.userId), [cleoId]);
    });

    test('…but not when they are the only approver: self-approval is common', () {
      queueTheRun();
      final candidates = evaluate(HookKind.approvalPending, approvalEvent(subId: 'sub', approverIds: const [bobId]));
      expect(candidates.map((c) => c.userId), [bobId]);
    });

    test('without a recorded run the requester is unknown and everybody is asked', () {
      final candidates = evaluate(
        HookKind.approvalPending,
        approvalEvent(subId: 'sub', approverIds: const [bobId, cleoId]),
      );
      expect(candidates.map((c) => c.userId), [bobId, cleoId]);
    });

    test('nobody is the actor of a pending approval', () {
      final view = viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub'));
      expect(approvalActor(view, state).id, isNull);
    });
  });

  group('approval-completed', () {
    test('the actor is the actual approver and the requester is told', () {
      queueTheRun();
      final body = approvalEvent(
        subId: 'sub',
        completed: true,
        status: 'approved',
        approverIds: const [adaId, cleoId],
        actualApproverId: adaId,
      );
      final view = viewOf(HookKind.approvalCompleted, body);
      expect(approvalActor(view, state).id, adaId);
      final candidates = evaluateApproval(view, state);
      expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [
        (adaId, Verb.approvalCompleted, 'approved'),
        (cleoId, Verb.approvalCompleted, 'approved'),
        (bobId, Verb.approvalCompleted, 'approved'),
      ], reason: 'the actor is dropped by the engine, not by the rule');
    });

    test('a rejection carries the status as its detail', () {
      final candidates = evaluate(
        HookKind.approvalCompleted,
        approvalEvent(subId: 'sub', completed: true, status: 'rejected'),
      );
      expect(candidates.single.detail, 'rejected');
    });

    test('a completed approval has no anchor: it opens the run', () {
      final candidates = evaluate(
        HookKind.approvalCompleted,
        approvalEvent(subId: 'sub', completed: true, status: 'approved'),
      );
      expect(candidates.single.anchor, isNull);
    });
  });
}
