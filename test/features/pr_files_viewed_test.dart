import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pr_detail_harness.dart';

/// R8's viewed marks on the Files tab. Azure DevOps has no server-side
/// viewed state (spike s64), so these live in the account's JSON cache and
/// a later iteration that touches the file clears them.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  Map<String, dynamic> change(String path, String objectId) => {
    'changeType': 'edit',
    'changeTrackingId': 1,
    'item': {'path': path, 'objectId': objectId, 'gitObjectType': 'blob'},
  };

  testWidgets('the header counts the files read, and a check marks one', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      changeEntries: [
        change('/spike/w39/one.txt', 'blob-1'),
        change('/spike/w39/two.txt', 'blob-2'),
      ],
    );
    await harness.pump(tester, initialTab: 'files');

    expect(find.text('0/2 viewed'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1/2 viewed'), findsOneWidget);
    expect(
      await harness.viewed.isViewed('o', 8401, '/spike/w39/one.txt'),
      isTrue,
    );

    // Tapping again takes the mark off.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('0/2 viewed'), findsOneWidget);
    expect(
      await harness.viewed.isViewed('o', 8401, '/spike/w39/one.txt'),
      isFalse,
    );
  });

  testWidgets('a mark made against an older blob is pruned on open', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      changeEntries: [change('/spike/w39/one.txt', 'blob-2')],
    );
    // Marked when the file was blob-1; the iteration has pushed since.
    await harness.viewed.markViewed(
      'o',
      8401,
      '/spike/w39/one.txt',
      iterationId: 1,
      objectId: 'blob-1',
    );
    await harness.pump(tester, initialTab: 'files');

    expect(find.text('0/1 viewed'), findsOneWidget);
    expect(
      await harness.viewed.isViewed('o', 8401, '/spike/w39/one.txt'),
      isFalse,
    );
  });

  testWidgets('a mark against the blob on screen survives the open', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      changeEntries: [change('/spike/w39/one.txt', 'blob-1')],
    );
    await harness.viewed.markViewed(
      'o',
      8401,
      '/spike/w39/one.txt',
      iterationId: 1,
      objectId: 'blob-1',
    );
    await harness.pump(tester, initialTab: 'files');
    expect(find.text('1/1 viewed'), findsOneWidget);
  });
}
