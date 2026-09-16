import 'package:boardhop/data/models/pr_check.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/features/pull_requests/widgets/completion_sheet.dart';
import 'package:boardhop/features/pull_requests/widgets/merge_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pr_detail_harness.dart';

/// R2's merge box and R3's completion sheet on scratch PR 8401, whose
/// target `scratch/policy-target` carries the blocking policies 192
/// (minimum reviewers) and 193 (squash + no fast-forward).
void main() {
  setUpAll(PrHarness.registerFallbacks);

  const pending = PrCheck(
    name: 'Minimum number of reviewers',
    state: PrCheckState.pending,
    isBlocking: true,
    detail: '1 approval required',
  );

  group('the button the state allows', () {
    test('everything passing offers Complete', () {
      expect(
        prPrimaryAction(pr: samplePr(), policies: policyTargetSet()),
        PrPrimaryAction.complete,
      );
    });

    test('a waiting blocking policy offers Set auto-complete', () {
      expect(
        prPrimaryAction(
          pr: samplePr(),
          policies: policyTargetSet(),
          checks: const [pending],
        ),
        PrPrimaryAction.setAutoComplete,
      );
    });

    test('without a blocking policy nothing is offered while it waits', () {
      // The service merges the moment auto-complete lands on a target with
      // no blocking policy (research/22 §1), so the button would lie.
      expect(
        prPrimaryAction(
          pr: samplePr(),
          policies: const PrPolicySet([]),
          checks: const [pending],
        ),
        isNull,
      );
    });

    test('conflicts take Complete away', () {
      expect(
        prPrimaryAction(
          pr: samplePr(mergeStatus: 'conflicts'),
          policies: policyTargetSet(),
        ),
        PrPrimaryAction.setAutoComplete,
      );
    });

    test('a draft offers Publish, an abandoned one Reactivate', () {
      expect(
        prPrimaryAction(pr: samplePr(isDraft: true), policies: null),
        PrPrimaryAction.publish,
      );
      expect(
        prPrimaryAction(pr: samplePr(status: 'abandoned'), policies: null),
        PrPrimaryAction.reactivate,
      );
    });

    test('a completed pull request and one already waiting offer nothing', () {
      expect(
        prPrimaryAction(pr: samplePr(status: 'completed'), policies: null),
        isNull,
      );
      expect(
        prPrimaryAction(
          pr: samplePr(
            autoCompleteSetBy: const {'displayName': 'Kelly', 'id': 'me'},
          ),
          policies: policyTargetSet(),
        ),
        isNull,
      );
    });
  });

  group('the sheet', () {
    test('offers only the strategies the policy allows', () {
      expect(policyTargetSet().allowedStrategies, {
        MergeStrategy.noFastForward,
        MergeStrategy.squash,
      });
    });

    test('opens on the remembered strategy, and on an allowed one when the '
        'remembered strategy is now forbidden', () {
      const remembered = PrCompletionOptions(
        mergeStrategy: MergeStrategy.squash,
      );
      expect(
        preferredStrategy(remembered, policyTargetSet().allowedStrategies),
        MergeStrategy.squash,
      );
      const rebase = PrCompletionOptions(mergeStrategy: MergeStrategy.rebase);
      expect(
        preferredStrategy(rebase, policyTargetSet().allowedStrategies),
        MergeStrategy.noFastForward,
      );
    });

    test('the optional policies are what "wait for optional" ignores', () {
      expect(optionalPolicyIds(policyTargetSet(withOptional: true)), [195]);
      expect(optionalPolicyIds(policyTargetSet()), isEmpty);
    });
  });

  testWidgets('a passing pull request completes through the sheet', (
    tester,
  ) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    when(() => harness.repo.complete('o', any(), any()))
        .thenAnswer((_) async => samplePr(status: 'completed'));
    await harness.pump(tester);

    expect(find.widgetWithText(FilledButton, 'Complete'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
    await tester.pumpAndSettle();

    // 193 allows squash and no fast-forward only.
    expect(find.text('Squash commit'), findsOneWidget);
    expect(find.text('Not allowed by policy'), findsNWidgets(2));

    await tester.tap(find.text('Squash commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete').last);
    await tester.pumpAndSettle();

    final options =
        verify(() => harness.repo.complete('o', any(), captureAny()))
                .captured
                .single
            as PrCompletionOptions;
    expect(options.mergeStrategy, MergeStrategy.squash);
    expect(options.deleteSourceBranch, isTrue);
    expect(options.transitionWorkItems, isTrue);
  });

  testWidgets('a blocked pull request sets auto-complete, and the optional '
      'toggle maps to autoCompleteIgnoreConfigIds', (tester) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(withOptional: true),
      checks: const [pending],
    );
    when(() => harness.repo.setAutoComplete('o', any(), any()))
        .thenAnswer((_) async => harness.pr);
    await harness.pump(tester);

    expect(
      find.widgetWithText(FilledButton, 'Set auto-complete'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Set auto-complete'));
    await tester.pumpAndSettle();

    // On by default; turning it off is what fills the ignore list.
    await tester.tap(find.text('Wait for optional policies too'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Set auto-complete').last,
    );
    await tester.pumpAndSettle();

    final options =
        verify(() => harness.repo.setAutoComplete('o', any(), captureAny()))
                .captured
                .single
            as PrCompletionOptions;
    expect(options.autoCompleteIgnoreConfigIds, [195]);
  });

  testWidgets('the sheet opens on the options the service remembered', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(
        completionOptions: const {
          'mergeStrategy': 'squash',
          'deleteSourceBranch': false,
          'transitionWorkItems': true,
          'mergeCommitMessage': 'Remembered message',
        },
      ),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.complete('o', any(), any()))
        .thenAnswer((_) async => harness.pr);
    await harness.pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
    await tester.pumpAndSettle();

    expect(find.text('Remembered message'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Complete').last);
    await tester.pumpAndSettle();

    final options =
        verify(() => harness.repo.complete('o', any(), captureAny()))
                .captured
                .single
            as PrCompletionOptions;
    expect(options.mergeStrategy, MergeStrategy.squash);
    expect(options.deleteSourceBranch, isFalse);
    expect(options.mergeCommitMessage, 'Remembered message');
  });

  testWidgets('the banner names who set auto-complete and cancels it', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(
        autoCompleteSetBy: const {'displayName': 'Kelly Kamm', 'id': 'me'},
        completionOptions: const {'mergeStrategy': 'noFastForward'},
      ),
      policies: policyTargetSet(),
      checks: const [pending],
    );
    when(() => harness.repo.cancelAutoComplete('o', any()))
        .thenAnswer((_) async => samplePr());
    await harness.pump(tester);

    expect(
      find.textContaining('Auto-complete set by Kelly Kamm'),
      findsOneWidget,
    );
    expect(find.textContaining('waiting on 1 check'), findsOneWidget);
    // The primary button is gone: the banner owns the one action left.
    expect(find.widgetWithText(FilledButton, 'Complete'), findsNothing);

    harness.becomes(samplePr());
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.cancelAutoComplete('o', any())).called(1);
  });

  testWidgets('conflicts are listed under the merge state', (tester) async {
    final harness = PrHarness(
      pr: samplePr(mergeStatus: 'conflicts'),
      policies: policyTargetSet(),
      conflicts: [
        PrConflict.fromJson(const {
          'conflictId': 1,
          'conflictType': 'editEdit',
          'conflictPath': '/spike/w39/one.txt',
        }),
      ],
    );
    await harness.pump(tester);

    expect(find.text('Merge conflicts'), findsOneWidget);
    expect(find.text('one.txt'), findsOneWidget);
    expect(find.textContaining('Edited on both sides'), findsOneWidget);
  });

  testWidgets('the required reviewers a policy names are shown by name', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(reviewers: [reviewerJson('rev-1', 'Kelly Kamm', vote: 10)]),
      policies: policyTargetSet(requiredReviewerIds: const ['REV-1']),
    );
    await harness.pump(tester);

    expect(find.text('Required by policy'), findsOneWidget);
    // Kelly appears twice: once in the policy block, once as a reviewer.
    expect(find.text('Kelly Kamm'), findsNWidgets(2));
    expect(find.text('Approved'), findsOneWidget);
  });
}
