import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pr_detail_harness.dart';

/// R2's overflow menu and the writes behind it, on scratch PR 8401.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  group('what the menu offers', () {
    test('an active pull request', () {
      expect(prMoreActions(samplePr()), [
        PrMoreAction.edit,
        PrMoreAction.markDraft,
        PrMoreAction.retarget,
        PrMoreAction.restartMerge,
        PrMoreAction.abandon,
        PrMoreAction.share,
        PrMoreAction.copyLink,
      ]);
    });

    test('a draft swaps Mark as draft for Publish', () {
      expect(
        prMoreActions(samplePr(isDraft: true)),
        contains(PrMoreAction.publish),
      );
      expect(
        prMoreActions(samplePr(isDraft: true)),
        isNot(contains(PrMoreAction.markDraft)),
      );
    });

    test('an abandoned one can only be reactivated, shared or copied', () {
      expect(prMoreActions(samplePr(status: 'abandoned')), [
        PrMoreAction.reactivate,
        PrMoreAction.share,
        PrMoreAction.copyLink,
      ]);
    });

    test('a completed one keeps Share and Copy link', () {
      expect(prMoreActions(samplePr(status: 'completed')), [
        PrMoreAction.share,
        PrMoreAction.copyLink,
      ]);
    });
  });

  testWidgets('Mark as draft confirms that the votes are reset (R4)', (
    tester,
  ) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    when(() => harness.repo.setDraft('o', any(), any()))
        .thenAnswer((_) async => samplePr(isDraft: true));
    await harness.pump(tester);

    await openMore(tester);
    await tester.tap(find.text('Mark as draft…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('every vote already cast is reset'),
      findsOneWidget,
    );

    harness.becomes(samplePr(isDraft: true));
    await tester.tap(find.widgetWithText(TextButton, 'Mark as draft'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.setDraft('o', any(), true)).called(1);
  });

  testWidgets('Publish asks nothing', (tester) async {
    final harness = PrHarness(
      pr: samplePr(isDraft: true),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.setDraft('o', any(), any()))
        .thenAnswer((_) async => samplePr());
    await harness.pump(tester);

    harness.becomes(samplePr());
    await openMore(tester);
    // Twice on screen: the merge box's own button and the menu item.
    await tester.tap(find.text('Publish').last);
    await tester.pumpAndSettle();
    verify(() => harness.repo.setDraft('o', any(), false)).called(1);
  });

  testWidgets('Change target branch picks a branch and retargets', (
    tester,
  ) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    when(() => harness.repo.retarget('o', any(), any()))
        .thenAnswer((_) async => samplePr(targetRef: 'refs/heads/main'));
    await harness.pump(tester);

    await openMore(tester);
    await tester.tap(find.text('Change target branch…'));
    await tester.pumpAndSettle();
    expect(find.text('scratch/policy-target'), findsWidgets);

    harness.becomes(samplePr(targetRef: 'refs/heads/main'));
    await tester.tap(find.text('main').last);
    await tester.pumpAndSettle();
    verify(() => harness.repo.retarget('o', any(), 'refs/heads/main'))
        .called(1);
  });

  testWidgets('Restart merge re-queues the merge', (tester) async {
    final harness = PrHarness(
      pr: samplePr(mergeStatus: 'conflicts'),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.restartMerge('o', any()))
        .thenAnswer((_) async => samplePr(mergeStatus: 'queued'));
    await harness.pump(tester);

    harness.becomes(samplePr(mergeStatus: 'queued'));
    await openMore(tester);
    await tester.tap(find.text('Restart merge'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.restartMerge('o', any())).called(1);
  });

  testWidgets('Copy link puts the web url on the clipboard', (tester) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    await harness.pump(tester);

    await openMore(tester);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(find.text('Link copied.'), findsOneWidget);
    expect(
      harness.pr.webUrl('o'),
      'https://dev.azure.com/o/DevOps%20Mobile%20App/_git/scratch/'
      'pullrequest/8401',
    );
  });

  testWidgets('Edit sends only what changed', (tester) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    when(
      () => harness.repo.update(
        'o',
        any(),
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async => samplePr());
    await harness.pump(tester);

    await openMore(tester);
    await tester.tap(find.text('Edit…'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Scratch policy PR'),
      'Scratch policy PR, renamed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    verify(
      () => harness.repo.update(
        'o',
        any(),
        title: 'Scratch policy PR, renamed',
        // Untouched, so it is not sent.
        description: null,
      ),
    ).called(1);
  });
}
