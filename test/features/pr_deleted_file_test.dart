import 'package:flutter_test/flutter_test.dart';

import 'pr_detail_harness.dart';

/// Customer feedback 2026-09-19: two draft pull requests opened to an empty
/// page. Being drafts was a coincidence; each deleted a file, and the delete
/// came back with `item.path: null`, which the changes parser cast to a
/// String. The TypeError was no AdoException, so the page caught nothing
/// and showed neither the pull request nor an error.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  testWidgets('a draft that deletes a file still renders', (tester) async {
    final harness = PrHarness(
      pr: samplePr(isDraft: true, targetRef: 'refs/heads/main'),
      changeEntries: [
        {
          'changeType': 'delete',
          'changeTrackingId': 1,
          'originalPath': '/src/gone.ts',
          'item': {'path': null, 'originalObjectId': 'old'},
        },
      ],
    );
    await harness.pump(tester);

    expect(find.text('Scratch policy PR'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gone.ts'), findsWidgets);
  });
}
