import 'package:boardhop/data/models/work_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pr_detail_harness.dart';

/// Linking and unlinking a work item from the Overview. The write is a work
/// item json-patch on its relations: the pull request side has no route for
/// it (`POST pullRequests/{id}/workitems` is 405).
void main() {
  setUpAll(PrHarness.registerFallbacks);

  WorkItem item(int id, String title) => WorkItem.fromJson({
    'id': id,
    'rev': 1,
    'fields': {
      'System.Title': title,
      'System.WorkItemType': 'Task',
      'System.State': 'Active',
    },
  });

  testWidgets('the + picker links through WorkItemRepository', (tester) async {
    final harness = PrHarness(pr: samplePr(), policies: policyTargetSet());
    // The `#` band the picker reuses reads the project's cached lists.
    when(() => harness.workItems.watchList('o', 'DevOps Mobile App', any()))
        .thenAnswer((_) => Stream.value([item(15545, 'Spike task one')]));
    when(
      () => harness.workItems.linkPullRequest(
        'o',
        any(),
        any(),
        any(),
        any(),
        project: any(named: 'project'),
      ),
    ).thenAnswer((_) async => item(15545, 'Spike task one'));
    await harness.pump(tester);

    expect(find.text('Linked work items (0)'), findsOneWidget);
    await tester.tap(find.byTooltip('Link a work item'));
    await tester.pumpAndSettle();
    expect(find.text('Spike task one'), findsOneWidget);

    harness.workItemsLinked = [item(15545, 'Spike task one')];
    await tester.tap(find.text('Spike task one'));
    await tester.pumpAndSettle();

    verify(
      () => harness.workItems.linkPullRequest(
        'o',
        15545,
        'proj',
        'repo',
        8401,
        project: 'DevOps Mobile App',
      ),
    ).called(1);
    expect(find.text('Linked work items (1)'), findsOneWidget);
  });

  testWidgets('the × on a row unlinks it after a confirm', (tester) async {
    final harness = PrHarness(
      pr: samplePr(),
      policies: policyTargetSet(),
      workItemsLinked: [item(15545, 'Spike task one')],
    );
    when(
      () => harness.workItems.unlinkPullRequest(
        'o',
        any(),
        any(),
        any(),
        any(),
        project: any(named: 'project'),
      ),
    ).thenAnswer((_) async => item(15545, 'Spike task one'));
    await harness.pump(tester);
    expect(find.text('Linked work items (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Unlink #15545'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink #15545?'), findsOneWidget);

    harness.workItemsLinked = const [];
    await tester.tap(find.widgetWithText(TextButton, 'Unlink'));
    await tester.pumpAndSettle();

    verify(
      () => harness.workItems.unlinkPullRequest(
        'o',
        15545,
        'proj',
        'repo',
        8401,
        project: 'DevOps Mobile App',
      ),
    ).called(1);
    expect(find.text('Linked work items (0)'), findsOneWidget);
  });

  testWidgets('a closed pull request has neither + nor ×', (tester) async {
    final harness = PrHarness(
      pr: samplePr(status: 'completed'),
      policies: policyTargetSet(),
      workItemsLinked: [item(15545, 'Spike task one')],
    );
    await harness.pump(tester);
    expect(find.byTooltip('Link a work item'), findsNothing);
    expect(find.byTooltip('Unlink #15545'), findsNothing);
  });
}
