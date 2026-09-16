import 'package:boardhop/data/models/pull_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pr_detail_harness.dart';

/// R14: chips on the Overview, a free-text editor with the project's tag
/// pool behind it, and one write per change.
void main() {
  setUpAll(PrHarness.registerFallbacks);

  testWidgets('the labels the sub-resource carries are shown as chips', (
    tester,
  ) async {
    final harness = PrHarness(
      pr: samplePr(labels: const ['boardhop-spike']),
      policies: policyTargetSet(),
    );
    await harness.pump(tester);
    expect(find.text('Labels (1)'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'boardhop-spike'), findsOneWidget);
  });

  testWidgets('adding one from the suggestions posts it', (tester) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    when(() => harness.repo.addLabel('o', any(), any()))
        .thenAnswer((_) async => const PrLabel(name: 'boardhop-spike'));
    await harness.pump(tester);
    expect(find.text('No labels.'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit labels'));
    await tester.pumpAndSettle();
    // The pool is the project's `wit/tags`, which labels share.
    expect(find.text('boardhop-spike-2'), findsOneWidget);
    await tester.tap(find.text('boardhop-spike'));
    await tester.pumpAndSettle();

    harness.becomes(samplePr(labels: const ['boardhop-spike']));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    verify(() => harness.repo.addLabel('o', any(), 'boardhop-spike')).called(1);
    verifyNever(() => harness.repo.removeLabel('o', any(), any()));
    expect(find.widgetWithText(Chip, 'boardhop-spike'), findsOneWidget);
  });

  testWidgets('removing a chip deletes it, and an unchanged list writes '
      'nothing', (tester) async {
    final harness = PrHarness(
      pr: samplePr(labels: const ['boardhop-spike']),
      policies: policyTargetSet(),
    );
    when(() => harness.repo.removeLabel('o', any(), any()))
        .thenAnswer((_) async {});
    await harness.pump(tester);

    // Open and close with no change: no write at all.
    await tester.tap(find.byTooltip('Edit labels'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    verifyNever(() => harness.repo.removeLabel('o', any(), any()));
    verifyNever(() => harness.repo.addLabel('o', any(), any()));

    await tester.tap(find.byTooltip('Edit labels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove boardhop-spike'));
    await tester.pumpAndSettle();
    harness.becomes(samplePr());
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    verify(() => harness.repo.removeLabel('o', any(), 'boardhop-spike'))
        .called(1);
    expect(find.text('No labels.'), findsOneWidget);
  });

  testWidgets('a closed pull request has no editor', (tester) async {
    final harness = PrHarness(
      pr: samplePr(status: 'completed', labels: const ['boardhop-spike']),
      policies: policyTargetSet(),
    );
    await harness.pump(tester);
    expect(find.byTooltip('Edit labels'), findsNothing);
    expect(find.widgetWithText(Chip, 'boardhop-spike'), findsOneWidget);
  });
}
