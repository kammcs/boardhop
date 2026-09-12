import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/features/pull_requests/widgets/thread_card.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PrThread thread({String status = PrThreadStatus.active}) => PrThread(
  id: 1,
  status: status,
  filePath: '/src/a.js',
  rightLine: 38,
  leftLine: null,
  trackedFromLine: null,
  comments: const [
    PrComment(
      id: 1,
      author: 'Javier Perez',
      content: 'This runs three queries.',
      publishedDate: null,
      identity: null,
    ),
  ],
);

void main() {
  late List<String> replies;
  late List<String> statuses;
  late bool replySucceeds;

  Widget host(PrThread t) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Scaffold(
      body: ThreadCard(
        thread: t,
        canAct: true,
        onReply: (text) async {
          replies.add(text);
          return replySucceeds;
        },
        onSetStatus: (status) async {
          statuses.add(status);
          return true;
        },
      ),
    ),
  );

  setUp(() {
    replies = [];
    statuses = [];
    replySucceeds = true;
  });

  testWidgets('an open thread offers Reply and a direct Resolve', (
    tester,
  ) async {
    await tester.pumpWidget(host(thread()));
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);

    await tester.tap(find.text('Resolve'));
    await tester.pump();
    expect(statuses, [PrThreadStatus.fixed]);
    expect(replies, isEmpty);
  });

  testWidgets('an empty box offers only Resolve, never a blank reply', (
    tester,
  ) async {
    await tester.pumpWidget(host(thread()));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    // Composer open, nothing typed: Cancel and Resolve, no Reply button.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
    expect(find.text('Reply & resolve'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reply'), findsNothing);
  });

  testWidgets('typing swaps in Reply and Reply & resolve', (tester) async {
    await tester.pumpWidget(host(thread()));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fixed in 4c71866');
    await tester.pumpAndSettle();
    expect(find.text('Resolve'), findsNothing);
    expect(find.text('Reply & resolve'), findsOneWidget);

    await tester.tap(find.text('Reply & resolve'));
    await tester.pumpAndSettle();
    expect(replies, ['Fixed in 4c71866']);
    expect(statuses, [PrThreadStatus.fixed]);
  });

  testWidgets('a failed reply does not resolve the thread', (tester) async {
    replySucceeds = false;
    await tester.pumpWidget(host(thread()));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply & resolve'));
    await tester.pumpAndSettle();
    expect(replies, ['nope']);
    expect(statuses, isEmpty);
  });

  testWidgets('a resolved thread pairs the reply with reactivating', (
    tester,
  ) async {
    await tester.pumpWidget(host(thread(status: PrThreadStatus.fixed)));
    // No direct Resolve on a settled thread; that lives in the menu.
    expect(find.text('Resolve'), findsNothing);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Reactivate'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'reopening');
    await tester.pumpAndSettle();
    // The plain reply says what the service will do with it anyway: a
    // comment on a settled thread reopens it (spike note, 2026-09-12).
    expect(find.text('Reply (reopens)'), findsOneWidget);
    await tester.tap(find.text('Reply & reactivate'));
    await tester.pumpAndSettle();
    expect(replies, ['reopening']);
    expect(statuses, [PrThreadStatus.active]);
  });
}
