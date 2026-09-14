import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/features/pull_requests/widgets/thread_card.dart';
import 'package:boardhop/features/shared/mention/mention_source.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/gestures.dart';
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

/// The GUID a picked mention posts as (research/16 §1).
const kellyGuid = '11111111-2222-3333-4444-555555555555';
const kelly = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: kellyGuid,
);

PrThread threadSaying(String content) => PrThread(
  id: 2,
  status: PrThreadStatus.active,
  filePath: null,
  rightLine: null,
  leftLine: null,
  trackedFromLine: null,
  comments: [
    PrComment(
      id: 1,
      author: 'Ada Example',
      content: content,
      publishedDate: null,
      identity: const IdentityRef(displayName: 'Ada Example', id: 'ada'),
    ),
  ],
);

void main() {
  late List<String> replies;
  late List<String> statuses;
  late bool replySucceeds;

  Widget host(
    PrThread t, {
    MentionSource? mentions,
    Map<String, String> names = const {},
    void Function(MentionKind kind, String id)? onOpenMention,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: Scaffold(
      body: ThreadCard(
        thread: t,
        canAct: true,
        mentions: mentions,
        mentionNames: names,
        onOpenMention: onOpenMention,
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

  testWidgets('a posted reply takes the keyboard with it', (tester) async {
    await tester.pumpWidget(host(thread()));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'done');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus ?? true, isTrue);

    await tester.tap(find.text('Reply').last);
    await tester.pumpAndSettle();
    expect(replies, ['done']);
    // Kelly, 2026-09-14: the keyboard goes away when a comment is posted.
    expect(find.byType(TextField), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
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

  testWidgets('a picked mention is posted as @<guid>, not as the name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        thread(),
        mentions: MentionSource(
          participants: () async => const [kelly],
          participantReason: 'On this pull request',
        ),
      ),
    );
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'thanks @kel');
    await tester.pumpAndSettle();
    expect(find.text('Kelly Kamm'), findsOneWidget);
    expect(find.text('On this pull request'), findsOneWidget);

    await tester.tap(find.text('Kelly Kamm'));
    await tester.pumpAndSettle();
    // On screen it reads as the name; the list is gone.
    expect(find.text('Kelly Kamm'), findsNothing);

    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(replies, ['thanks @<$kellyGuid>']);
  });

  testWidgets('an unresolved @word is called out above the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(host(thread()));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'thanks @kelly');
    await tester.pumpAndSettle();
    expect(find.textContaining('@kelly is not a mention'), findsOneWidget);
  });

  testWidgets('a comment mentioning a GUID reads as the name', (tester) async {
    await tester.pumpWidget(
      host(
        threadSaying('nice one @<$kellyGuid>'),
        names: const {kellyGuid: 'Kelly Kamm'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('@Kelly Kamm'), findsOneWidget);
    expect(find.textContaining(kellyGuid), findsNothing);
  });

  testWidgets('a GUID nobody answers for reads @someone, never the GUID', (
    tester,
  ) async {
    await tester.pumpWidget(host(threadSaying('ping @<$kellyGuid>')));
    await tester.pumpAndSettle();
    expect(find.textContaining('@someone'), findsOneWidget);
    expect(find.textContaining(kellyGuid), findsNothing);
  });

  testWidgets('#15545 in a comment is drawn and opens that work item', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      host(
        threadSaying('fixes #15545'),
        onOpenMention: (kind, id) => opened.add('${kind.name}:$id'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('#15545'), findsOneWidget);

    // The body is selectable, so it renders through `EditableText` rather
    // than a `RenderParagraph` and `tapOnText` has nothing to measure; the
    // span's own recogniser is what a tap reaches (`RenderEditable`
    // propagates pointer events to them).
    final recognizers = <GestureRecognizer>[];
    tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .textSpan!
        .visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) {
            recognizers.add(span.recognizer!);
          }
          return true;
        });
    expect(recognizers, hasLength(1));
    (recognizers.single as TapGestureRecognizer).onTap!();
    expect(opened, ['workItem:15545']);
  });
}
