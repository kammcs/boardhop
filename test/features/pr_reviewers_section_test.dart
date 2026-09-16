import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/pull_requests/widgets/reviewers_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pr_detail_harness.dart';

/// R12's reviewer row and its picker.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  PrReviewer reviewerOf(PullRequest pr, String id) =>
      pr.reviewers.firstWhere((r) => r.id == id);

  group('what each row offers', () {
    test('somebody else, seen by the author', () {
      final pr = samplePr(
        createdById: 'me',
        reviewers: [reviewerJson('rev', 'Kelly Kamm', vote: 10)],
      );
      expect(
        reviewerActions(reviewer: reviewerOf(pr, 'rev'), pr: pr, meId: 'me'),
        [
          PrReviewerAction.makeRequired,
          PrReviewerAction.resetVote,
          PrReviewerAction.remove,
        ],
      );
    });

    test('Reset vote is the author\'s, and only on a vote that exists', () {
      final pr = samplePr(
        createdById: 'me',
        reviewers: [reviewerJson('rev', 'Kelly Kamm')],
      );
      expect(
        reviewerActions(reviewer: reviewerOf(pr, 'rev'), pr: pr, meId: 'me'),
        isNot(contains(PrReviewerAction.resetVote)),
      );
      expect(
        reviewerActions(reviewer: reviewerOf(pr, 'rev'), pr: pr, meId: 'other'),
        isNot(contains(PrReviewerAction.resetVote)),
      );
    });

    test(
      'my own row flags and declines; a required one can be made optional',
      () {
        final pr = samplePr(
          reviewers: [reviewerJson('me', 'Me', isRequired: true)],
        );
        expect(
          reviewerActions(reviewer: reviewerOf(pr, 'me'), pr: pr, meId: 'me'),
          [
            PrReviewerAction.makeOptional,
            PrReviewerAction.flag,
            PrReviewerAction.decline,
            PrReviewerAction.remove,
          ],
        );
      },
    );

    test('the creator cannot decline their own pull request (HTTP 500)', () {
      final pr = samplePr(
        createdById: 'me',
        reviewers: [reviewerJson('me', 'Me')],
      );
      expect(
        reviewerActions(reviewer: reviewerOf(pr, 'me'), pr: pr, meId: 'me'),
        isNot(contains(PrReviewerAction.decline)),
      );
    });

    test('a closed pull request offers nothing', () {
      final pr = samplePr(
        status: 'completed',
        reviewers: [reviewerJson('rev', 'Kelly Kamm')],
      );
      expect(
        reviewerActions(reviewer: reviewerOf(pr, 'rev'), pr: pr, meId: 'me'),
        isEmpty,
      );
    });
  });

  testWidgets('the row says the vote, whether it is required and the flag', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(
        reviewers: [
          reviewerJson(
            'rev',
            'Kelly Kamm',
            vote: -5,
            isRequired: true,
            isFlagged: true,
          ),
        ],
      ),
      policies: policyTargetSet(),
    );
    await harness.pump(tester);
    expect(find.text('Waiting for author · Required'), findsOneWidget);
    expect(find.byTooltip('Flagged for the author'), findsOneWidget);
  });

  testWidgets('Make required goes through setRequired', (tester) async {
    final harness = PrHarness(
      pr: samplePr(reviewers: [reviewerJson('rev', 'Kelly Kamm')]),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.setRequired('o', any(), 'rev', any())).thenAnswer(
      (_) async => PrReviewer.fromJson(
        reviewerJson('rev', 'Kelly Kamm', isRequired: true),
      ),
    );
    await harness.pump(tester);

    await tester.tap(find.byTooltip('Reviewer actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make required'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.setRequired('o', any(), 'rev', true)).called(1);
  });

  testWidgets('Remove takes the reviewer off', (tester) async {
    final harness = PrHarness(
      pr: samplePr(reviewers: [reviewerJson('rev', 'Kelly Kamm')]),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.removeReviewer('o', any(), 'rev'))
        .thenAnswer((_) async {});
    await harness.pump(tester);

    harness.becomes(samplePr());
    await tester.tap(find.byTooltip('Reviewer actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.removeReviewer('o', any(), 'rev')).called(1);
    expect(find.text('No reviewers yet.'), findsOneWidget);
  });

  testWidgets('my own row can be flagged for the author', (tester) async {
    final harness = PrHarness(
      pr: samplePr(reviewers: [reviewerJson('me', 'Me')]),
      policies: policyTargetSet(),
    );
    when(
      () => harness.repo.flag(
        'o',
        any(),
        'me',
        isFlagged: any(named: 'isFlagged'),
      ),
    ).thenAnswer(
      (_) async =>
          PrReviewer.fromJson(reviewerJson('me', 'Me', isFlagged: true)),
    );
    await harness.pump(tester);

    await tester.tap(find.byTooltip('Reviewer actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flag for attention'));
    await tester.pumpAndSettle();
    verify(() => harness.repo.flag('o', any(), 'me')).called(1);
  });

  testWidgets(
    'Add reviewer offers the project teams and adds one as required',
    (tester) async {
      final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
      when(
        () => harness.repo.addReviewer(
          'o',
          any(),
          any(),
          isRequired: any(named: 'isRequired'),
        ),
      ).thenAnswer(
        (_) async => PrReviewer.fromJson(
          reviewerJson('team-guid', 'Boardhop Team', isContainer: true),
        ),
      );
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Add reviewer'));
      await tester.pumpAndSettle();
      expect(find.text('Boardhop Team'), findsOneWidget);

      await tester.tap(find.text('Required'));
      await tester.pumpAndSettle();
      harness.becomes(
        samplePr(
          reviewers: [
            reviewerJson(
              'team-guid',
              'Boardhop Team',
              isContainer: true,
              isRequired: true,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Boardhop Team'));
      await tester.pumpAndSettle();

      verify(
        () =>
            harness.repo.addReviewer('o', any(), 'team-guid', isRequired: true),
      ).called(1);
      expect(find.textContaining('· Required · team'), findsOneWidget);
    },
  );

  testWidgets('a person picked from the search is resolved to a GUID first', (
    tester,
  ) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    // Touched first: the stubs are built lazily and their own `when` calls
    // cannot run inside another one.
    final people = harness.stubs.people;
    const hit = IdentityRef(
      displayName: 'Kelly Kamm',
      uniqueName: 'kelly@kammcs.com',
      descriptor: 'aad.abc',
    );
    when(() => people.searchPeople('o', 'proj', 'kelly'))
        .thenAnswer((_) async => const [hit]);
    when(() => people.resolveIdentityId('o', hit)).thenAnswer(
      (_) async => const IdentityRef(
        displayName: 'Kelly Kamm',
        uniqueName: 'kelly@kammcs.com',
        id: 'kelly-guid',
      ),
    );
    when(
      () => harness.repo.addReviewer(
        'o',
        any(),
        any(),
        isRequired: any(named: 'isRequired'),
      ),
    ).thenAnswer(
      (_) async =>
          PrReviewer.fromJson(reviewerJson('kelly-guid', 'Kelly Kamm')),
    );
    await harness.pump(tester);

    await tester.tap(find.byTooltip('Add reviewer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'kelly');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kelly@kammcs.com'));
    await tester.pumpAndSettle();

    verify(
      () =>
          harness.repo.addReviewer('o', any(), 'kelly-guid', isRequired: false),
    ).called(1);
  });
}
