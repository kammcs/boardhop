import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:boardhop_relay/src/routing/work_item_rules.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';

/// research/14 §2.1, one test per row. The rules are pure functions over a
/// [RoutingView] and the routing state, so these call them directly; the
/// engine's own rules (actor, priority, preferences, caps) are in
/// `routing_engine_test.dart`.
void main() {
  late MemoryRoutingState state;

  setUp(() => state = MemoryRoutingState());

  List<Candidate> evaluate(HookKind kind, Map<String, Object?> body) => evaluateWorkItem(viewOf(kind, body), state);

  /// `revisedBy` on every `workitem.updated` fixture is Ada.
  const actor = adaId;

  group('workitem.updated — assignment', () {
    test('a new assignee is asked, and the previous one is told', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.AssignedTo': {'newValue': identity(bobId, 'Bob Example'), 'oldValue': identity(cleoId, 'Cleo')},
            'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
          },
        ),
      );
      expect(candidates.map((c) => (c.userId, c.verb)), [(bobId, Verb.assigned), (cleoId, Verb.reassigned)]);
    });

    test('an assignment that was previously unassigned tells only the new assignee', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.AssignedTo': {'newValue': identity(bobId, 'Bob Example')},
          },
        ),
      );
      expect(candidates.map((c) => c.userId), [bobId]);
    });
  });

  group('workitem.updated — state', () {
    test('a state change reaches the assignee and the creator, with the new state as detail', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          state: 'Done',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.State': {'newValue': 'Done', 'oldValue': 'Active'},
            'System.Reason': {'newValue': 'Completed'},
            'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
          },
        ),
      );
      // The fixture's creator is Cleo.
      expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [
        (bobId, Verb.stateChanged, 'Done'),
        (cleoId, Verb.stateChanged, 'Done'),
      ]);
    });

    test('the creator is not told twice when they are also the assignee', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(cleoId, 'Cleo Example'),
          changes: {
            'System.State': {'newValue': 'Done'},
          },
        ),
      );
      expect(candidates.map((c) => c.userId), [cleoId]);
    });
  });

  group('workitem.updated — edits', () {
    test('a title edit selects the assignee with `edited`, which the defaults then drop', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.Title': {'newValue': 'Renamed', 'oldValue': 'Old'},
            'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
            'System.Rev': {'newValue': 12},
          },
        ),
      );
      expect(candidates.map((c) => (c.userId, c.verb)), [(bobId, Verb.edited)]);
    });

    test('a bare revision bump — the comment field set without History — is noise', () {
      final body = workItemUpdated(
        subId: 'sub',
        currentAssignedTo: identity(bobId, 'Bob Example'),
        changes: {
          'System.Rev': {'newValue': 12, 'oldValue': 11},
          'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
          'System.Watermark': {'newValue': 77},
        },
      );
      expect(isWorkItemNoise(viewOf(HookKind.wiUpdated, body)), isTrue);
      expect(evaluate(HookKind.wiUpdated, body), isEmpty);
    });
  });

  group('the comment-shaped workitem.updated is the comment event', () {
    test('it is classified as the comment, not as noise', () {
      final view = viewOf(HookKind.wiUpdated, workItemCommentNoise(subId: 'sub'));
      expect(isWorkItemComment(view), isTrue);
      expect(isWorkItemNoise(view), isFalse);
      expect(view.actorId, actor, reason: 'only this post of the pair carries revisedBy.id');
    });

    test('assignee and creator hear `commented`, anchored on the comment', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemCommentNoise(subId: 'sub')
          ..['resource'] = _withAssignee(workItemCommentNoise(subId: 'sub'), identity(bobId, 'Bob Example')),
      );
      expect(candidates.map((c) => (c.userId, c.verb, c.anchor)), [
        (bobId, Verb.commented, 'comment:4'),
        (cleoId, Verb.commented, 'comment:4'),
      ]);
    });

    test('a mention in the comment selects the mentioned person with `mentioned`', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemCommentNoise(subId: 'sub', history: 'Look ${htmlMention(bobId, 'Bob Example')} — $canary'),
      );
      expect(candidates.first.userId, bobId);
      expect(candidates.first.verb, Verb.mentioned);
      expect(candidates.first.anchor, 'comment:4');
    });

    test('a mention through an ordinary edit reaches only the mentioned person', () {
      final candidates = evaluate(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(cleoId, 'Cleo Example'),
          currentHistory: 'ping ${htmlMention(bobId, 'Bob Example')}',
          changes: {
            'System.History': {'newValue': 'ping ${htmlMention(bobId, 'Bob Example')}'},
            'System.Title': {'newValue': 'and a retitle'},
          },
        ),
      );
      expect(candidates.where((c) => c.verb == Verb.mentioned).map((c) => c.userId), [bobId]);
    });
  });

  group('the other two work item events', () {
    test('workitem.commented notifies nobody: its body names no identity', () {
      expect(evaluate(HookKind.wiCommented, workItemCommented(subId: 'sub')), isEmpty);
    });

    test('workitem.created selects the assignee', () {
      final candidates = evaluate(HookKind.wiCreated, workItemCreated(subId: 'sub'));
      expect(candidates.map((c) => (c.userId, c.verb)), [(bobId, Verb.created)]);
    });

    test('workitem.created with nobody assigned selects nobody', () {
      final body = workItemCreated(subId: 'sub');
      (((body['resource']! as Map)['fields']!) as Map).remove('System.AssignedTo');
      expect(evaluate(HookKind.wiCreated, body), isEmpty);
    });

    test('the actor of workitem.created is its creator, which has no revisedBy', () {
      final view = viewOf(HookKind.wiCreated, workItemCreated(subId: 'sub'));
      expect(view.actorId, isNull);
      expect(workItemActor(view, state).id, cleoId);
    });
  });

  test('every work item event records the project name for the routes', () {
    evaluate(HookKind.wiCreated, workItemCreated(subId: 'sub'));
    expect(state.projectName(fixtureOrg, projectGuid), 'Contoso Demo');
  });
}

/// The comment fixture has no assignee; this puts one into its revision.
Map<String, Object?> _withAssignee(Map<String, Object?> body, Map<String, Object?> assignee) {
  final resource = Map<String, Object?>.from(body['resource']! as Map);
  final revision = Map<String, Object?>.from(resource['revision']! as Map);
  final fields = Map<String, Object?>.from(revision['fields']! as Map);
  fields['System.AssignedTo'] = assignee;
  revision['fields'] = fields;
  resource['revision'] = revision;
  return resource;
}
