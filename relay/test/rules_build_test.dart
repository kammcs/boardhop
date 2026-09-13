import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/routing/build_rules.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';

/// research/14 §2.3 and decision D3.
void main() {
  late MemoryRoutingState state;

  setUp(() => state = MemoryRoutingState());

  List<Candidate> evaluate(Map<String, Object?> body) => evaluateBuild(viewOf(HookKind.buildComplete, body), state);

  group('a finished build', () {
    const verbs = {'failed': Verb.buildFailed, 'partiallySucceeded': Verb.buildPartial, 'canceled': Verb.buildCanceled};

    for (final entry in verbs.entries) {
      test('${entry.key} reaches requestedFor and requestedBy', () {
        final candidates = evaluate(buildComplete(subId: 'sub', result: entry.key));
        expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [
          (bobId, entry.value, entry.key),
          (adaId, entry.value, entry.key),
        ]);
      });
    }

    test('one person who both queued it and owns it is selected once', () {
      final candidates = evaluate(buildComplete(subId: 'sub', requestedForId: adaId, requestedById: adaId));
      expect(candidates.map((c) => c.userId), [adaId]);
    });

    test('a plain success is selected as buildSucceeded, which the defaults drop', () {
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.map((c) => (c.userId, c.verb)), [(bobId, Verb.buildSucceeded)]);
    });

    test('a success reaches only the person the build was for', () {
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.map((c) => c.userId), isNot(contains(adaId)));
    });

    test('a result the relay does not know selects nobody', () {
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'none'));
      expect(candidates, isEmpty);
    });
  });

  group('"fixed" detection', () {
    test('a success right after a failure on the same definition and branch is a fix', () {
      evaluate(buildComplete(subId: 'sub', result: 'failed'));
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [(bobId, Verb.buildFixed, 'succeeded')]);
    });

    test('a success on a different branch is not a fix', () {
      evaluate(buildComplete(subId: 'sub', result: 'failed', sourceBranch: 'refs/heads/topic'));
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.single.verb, Verb.buildSucceeded);
    });

    test('a success on a different definition is not a fix', () {
      evaluate(buildComplete(subId: 'sub', result: 'failed', definitionId: 140));
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.single.verb, Verb.buildSucceeded);
    });

    test('two successes in a row: the second is not a fix', () {
      evaluate(buildComplete(subId: 'sub', result: 'failed'));
      evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      final candidates = evaluate(buildComplete(subId: 'sub', result: 'succeeded'));
      expect(candidates.single.verb, Verb.buildSucceeded);
    });

    test('the last result is remembered per definition and branch', () {
      evaluate(buildComplete(subId: 'sub', result: 'partiallySucceeded'));
      final row = state.build(fixtureOrg, projectGuid, '139', 'refs/heads/main')!;
      expect(row.lastResult, 'partiallySucceeded');
      expect(row.buildId, '20163');
      expect(row.wasFailure, isTrue);
    });
  });

  test('the actor of a build is requestedBy', () {
    final view = viewOf(HookKind.buildComplete, buildComplete(subId: 'sub'));
    expect(buildActor(view, state).id, adaId);
  });

  test('a build records the project name for the run route', () {
    evaluate(buildComplete(subId: 'sub'));
    expect(state.projectName(fixtureOrg, projectGuid), 'Contoso Demo');
  });

  test('a build without a definition still notifies, it simply cannot detect a fix', () {
    final body = buildComplete(subId: 'sub', result: 'succeeded');
    ((body['resource']! as Map)['definition']! as Map).remove('id');
    final candidates = evaluateBuild(viewOf(HookKind.buildComplete, body), state);
    expect(candidates.single.verb, Verb.buildSucceeded);
    expect(state.builds, isEmpty);
  });
}
