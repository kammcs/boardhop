import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pr_detail_harness.dart';

/// R11: the Comments tab's Activity chip reveals the system threads — the
/// votes, pushes and auto-complete events the service writes — as quiet
/// rows. The default view is comments only, as it always was.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  Map<String, dynamic> comment(int id, String text) => {
    'id': id,
    'status': 'active',
    'publishedDate': '2026-09-16T10:00:00Z',
    'comments': [
      {
        'id': 1,
        'commentType': 'text',
        'content': text,
        'publishedDate': '2026-09-16T10:00:00Z',
        'author': {'displayName': 'Ada Example', 'id': 'author'},
      },
    ],
  };

  /// A system thread as the service writes it: `commentType: system`, the
  /// kind in `properties.CodeReviewThreadType`, and `{1}` standing for the
  /// actor in `identities`.
  Map<String, dynamic> system(int id, String kind, String text) => {
    'id': id,
    'status': 'closed',
    'publishedDate': '2026-09-16T11:00:00Z',
    'properties': {
      'CodeReviewThreadType': {r'$type': 'System.String', r'$value': kind},
    },
    'identities': {
      '1': {'displayName': 'Kelly Kamm', 'id': 'me'},
    },
    'comments': [
      {
        'id': 1,
        'commentType': 'system',
        'content': text,
        'publishedDate': '2026-09-16T11:00:00Z',
      },
    ],
  };

  testWidgets('system threads appear only once the chip is on', (tester) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      threads: [
        comment(1, 'A real comment'),
        system(2, 'AutoCompleteUpdate', '{1} set auto-complete'),
        system(3, 'VoteUpdate', '{1} approved'),
      ],
    );
    await harness.pump(tester);
    await tester.tap(find.textContaining('Comments'));
    await tester.pumpAndSettle();

    expect(find.text('A real comment'), findsOneWidget);
    expect(find.text('Kelly Kamm set auto-complete'), findsNothing);

    // The chip row scrolls sideways on a phone.
    await tester.ensureVisible(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Kelly Kamm set auto-complete'), findsOneWidget);
    expect(find.text('Kelly Kamm approved'), findsOneWidget);
    expect(find.text('A real comment'), findsOneWidget);
    // The filter chips still count the comments, not the events.
    expect(find.text('All (1)'), findsOneWidget);
  });

  testWidgets('the Resolved filter hides the comments but keeps the events', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      threads: [
        comment(1, 'A real comment'),
        system(2, 'RefUpdate', '{1} pushed a commit'),
      ],
    );
    await harness.pump(tester);
    await tester.tap(find.textContaining('Comments'));
    await tester.pumpAndSettle();
    // The chip row scrolls sideways on a phone.
    await tester.ensureVisible(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Activity'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Resolved (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved (0)'));
    await tester.pumpAndSettle();

    expect(find.text('A real comment'), findsNothing);
    expect(find.text('Kelly Kamm pushed a commit'), findsOneWidget);
  });
}
