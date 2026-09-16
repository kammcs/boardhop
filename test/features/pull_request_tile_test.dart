import 'package:boardhop/features/pull_requests/widgets/pull_request_tile.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pr_detail_harness.dart';

/// R13's inbox row: the auto-complete badge and the reason label.
void main() {
  Future<void> pumpTile(WidgetTester tester, {required Widget tile}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(body: ListView(children: [tile])),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('why the row is in front of you', () {
    test('the author wins over every other reason', () {
      expect(
        PullRequestTile.reasonFor(
          samplePr(
            createdById: 'me',
            reviewers: [reviewerJson('me', 'Me', isRequired: true)],
          ),
          'me',
        ),
        'Author',
      );
    });

    test('a required reviewer is told so', () {
      expect(
        PullRequestTile.reasonFor(
          samplePr(reviewers: [reviewerJson('me', 'Me', isRequired: true)]),
          'me',
        ),
        'Required reviewer',
      );
      expect(
        PullRequestTile.reasonFor(
          samplePr(reviewers: [reviewerJson('me', 'Me')]),
          'me',
        ),
        'Reviewer',
      );
    });

    test('a draft with no other reason says Draft', () {
      expect(PullRequestTile.reasonFor(samplePr(isDraft: true), 'me'), 'Draft');
      expect(PullRequestTile.reasonFor(samplePr(), 'me'), isNull);
    });

    test('without an identity there is no reason to give', () {
      expect(
        PullRequestTile.reasonFor(
          samplePr(reviewers: [reviewerJson('me', 'Me')]),
          null,
        ),
        isNull,
      );
    });
  });

  testWidgets('the auto-complete badge rides beside the draft one', (
    tester,
  ) async {
    await pumpTile(
      tester,
      tile: PullRequestTile(
        pr: samplePr(
          autoCompleteSetBy: const {'displayName': 'Kelly Kamm', 'id': 'me'},
          reviewers: [reviewerJson('me', 'Me', isRequired: true)],
        ),
        meId: 'me',
        onTap: () {},
      ),
    );
    expect(find.byType(AutoCompleteBadge), findsOneWidget);
    expect(
      find.textContaining('scratch · !8401 · Required reviewer'),
      findsOneWidget,
    );
  });

  testWidgets('a pull request with nothing set has neither badge', (
    tester,
  ) async {
    await pumpTile(
      tester,
      tile: PullRequestTile(pr: samplePr(), meId: 'me', onTap: () {}),
    );
    expect(find.byType(AutoCompleteBadge), findsNothing);
    expect(find.textContaining('scratch · !8401'), findsOneWidget);
    expect(find.textContaining('Reviewer'), findsNothing);
  });
}
