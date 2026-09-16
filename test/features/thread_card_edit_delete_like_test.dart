import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/features/pull_requests/widgets/thread_card.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'diff_page_harness.dart';

/// R9's comment tools on the card the diff and the conversation share:
/// a per-comment menu on my own comments, the "edited" marker, the web's
/// deleted stub, and likes with their count and names.
void main() {
  late List<String> edits;
  late List<int> deletes;
  late List<bool> likes;
  late bool succeeds;

  Widget host(
    PrThread thread, {
    String? meId = 'me',
    bool withEdit = true,
    bool withDelete = true,
    bool withLike = true,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: ThreadCard(
            thread: thread,
            canAct: true,
            meId: meId,
            onReply: (_) async => true,
            onSetStatus: (_) async => true,
            onEditComment: withEdit
                ? (comment, text) async {
                    edits.add(text);
                    return succeeds;
                  }
                : null,
            onDeleteComment: withDelete
                ? (comment) async {
                    deletes.add(comment.id);
                    return succeeds;
                  }
                : null,
            onLikeComment: withLike
                ? (comment, like) async {
                    likes.add(like);
                    return succeeds;
                  }
                : null,
          ),
        ),
      ),
    ),
  );

  setUp(() {
    edits = [];
    deletes = [];
    likes = [];
    succeeds = true;
  });

  testWidgets('my own comment carries the menu; somebody else\'s does not', (
    tester,
  ) async {
    await tester.pumpWidget(host(prThread(id: 1, rightLine: 2)));
    expect(find.byTooltip('This comment'), findsOneWidget);

    await tester.pumpWidget(
      host(prThread(id: 1, rightLine: 2, authorId: 'someone-else')),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('This comment'), findsNothing);
  });

  testWidgets('Edit opens the comment in place and Save sends the text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(prThread(id: 1, rightLine: 2, content: 'three queries here')),
    );
    await tester.tap(find.byTooltip('This comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Prefilled with what the service holds.
    expect(find.widgetWithText(TextField, 'three queries here'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'two queries now');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(edits, ['two queries now']);
    // The editor closes on a write that went through.
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('Cancel leaves the comment as it was', (tester) async {
    await tester.pumpWidget(
      host(prThread(id: 1, rightLine: 2, content: 'as it was')),
    );
    await tester.tap(find.byTooltip('This comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'never mind');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(edits, isEmpty);
    expect(find.textContaining('as it was'), findsOneWidget);
  });

  testWidgets('a refused edit keeps the editor open with the text in it', (
    tester,
  ) async {
    succeeds = false;
    await tester.pumpWidget(host(prThread(id: 1, rightLine: 2)));
    await tester.tap(find.byTooltip('This comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'try again');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(edits, ['try again']);
    expect(find.text('Save'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'try again'), findsWidgets);
  });

  testWidgets('Delete asks first, then deletes', (tester) async {
    await tester.pumpWidget(host(prThread(id: 1, rightLine: 2)));
    await tester.tap(find.byTooltip('This comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this comment?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(deletes, isEmpty);

    await tester.tap(find.byTooltip('This comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deletes, [1]);
  });

  testWidgets('a deleted comment reads as the web\'s stub', (tester) async {
    await tester.pumpWidget(
      host(prThread(id: 1, rightLine: 2, content: 'gone', deleted: true)),
    );
    expect(find.text('This comment was deleted'), findsOneWidget);
    expect(find.textContaining('gone'), findsNothing);
    // Nothing to edit, delete or like on a stub.
    expect(find.byTooltip('This comment'), findsNothing);
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
  });

  testWidgets('an edited comment says so', (tester) async {
    await tester.pumpWidget(host(prThread(id: 1, rightLine: 2)));
    expect(find.textContaining('edited'), findsNothing);

    await tester.pumpWidget(
      host(prThread(id: 1, rightLine: 2, editedAt: '2026-09-16T11:00:00Z')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('the like button toggles at once and counts', (tester) async {
    await tester.pumpWidget(
      host(
        prThread(
          id: 1,
          rightLine: 2,
          likes: const [
            {'id': 'ada', 'displayName': 'Ada Example'},
          ],
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.byTooltip('Ada Example'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pump();
    // Optimistic: the count moves with the tap, before the write answers.
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    await tester.pumpAndSettle();
    expect(likes, [true]);

    await tester.tap(find.byIcon(Icons.thumb_up));
    await tester.pumpAndSettle();
    expect(likes, [true, false]);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a refused like rolls the count back', (tester) async {
    succeeds = false;
    await tester.pumpWidget(host(prThread(id: 1, rightLine: 2)));
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();
    expect(likes, [true]);
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('no callbacks means the card is exactly what it was', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        prThread(id: 1, rightLine: 2),
        withEdit: false,
        withDelete: false,
        withLike: false,
      ),
    );
    expect(find.byTooltip('This comment'), findsNothing);
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.text('Reply'), findsOneWidget);
  });
}
