import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/anchor_highlight.dart';
import 'package:boardhop/features/work_items/work_item_detail_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class _Repo extends Mock implements WorkItemRepository {}

class _Forms extends Mock implements WorkItemFormRepository {}

class _Queue extends Mock implements WriteQueue {}

class _AuthService extends Mock implements AuthService {}

/// research/14 §4.2: a pushed work item comment lands on that comment —
/// the page selects the Comments tab, scrolls the comment into view and
/// tints it for two seconds — and a comment id that is not in the list
/// degrades to the top of the discussion with no error.
/// The scratch person every mention test picks, with the identity GUID a
/// mention needs (research/16 §1).
const kellyGuid = '11111111-2222-3333-4444-555555555555';
const kelly = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: kellyGuid,
);

void main() {
  // `any()` for an upload's bytes needs a fallback instance.
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  const comments = 12;

  final item = WorkItem(
    id: 15545,
    rev: 3,
    fields: const {
      'System.WorkItemType': 'Task',
      'System.Title': 'Anchor the pushed comment',
      'System.State': 'Active',
      'System.AreaPath': 'Scratch',
      'System.IterationPath': 'Scratch',
    },
  );

  late _Repo repo;
  late _Forms forms;
  late _Queue queue;
  late MentionStubs stubs;
  late MentionPullRequests prs;

  setUp(() {
    repo = _Repo();
    forms = _Forms();
    queue = _Queue();
    // The Discussion composer's picker is built in the background; these
    // answer its reads with nothing (research/16 §4.5).
    stubs = mentionStubs();
    prs = MentionPullRequests();
    stubMentionPullRequests(prs);
    when(() => forms.projectId('o', 'p')).thenAnswer((_) async => 'proj');
    when(() => forms.defaultTeamId('o', 'p')).thenAnswer((_) async => 'team');
    when(() => repo.watchList('o', 'p', any()))
        .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
    when(() => stubs.people.teamMembers('o', 'proj', 'team'))
        .thenAnswer((_) async => const [kelly]);
    when(() => repo.types('o', 'p')).thenAnswer(
      (_) async => const [
        WorkItemType(name: 'Task', referenceName: 'Microsoft.VSTS.Task'),
      ],
    );
    when(() => repo.refreshItem('o', 'p', 15545)).thenAnswer((_) async => item);
    when(() => repo.watchItem('o', 15545))
        .thenAnswer((_) => Stream<WorkItem?>.value(item));
    when(() => repo.comments('o', 'p', 15545)).thenAnswer(
      (_) async => [
        for (var i = 1; i <= comments; i++)
          WorkItemComment(
            id: 2000 + i,
            text: 'comment $i',
            renderedText: '<p>comment $i</p>',
            // Somebody other than [kelly], so the mention list has one
            // "Kelly Kamm" row rather than two people who read alike.
            createdBy: const IdentityRef(
              displayName: 'Ada Example',
              uniqueName: 'ada@example.test',
              id: 'ada-id',
            ),
            createdDate: DateTime.utc(2026, 9, 13, 10, i),
          ),
      ],
    );
    // Both are niceties the page swallows when the service refuses them.
    when(() => forms.formSpec('o', 'p', 'Task'))
        .thenThrow(const AdoForbiddenException('no spec here'));
    when(() => forms.backlogTypes('o', 'p'))
        .thenThrow(const AdoForbiddenException('no backlog here'));
  });

  Future<void> pump(WidgetTester tester, {int? commentId, String? tab}) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final authService = _AuthService();
    when(() => authService.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'tok');
    when(() => authService.accountById(any())).thenReturn(null);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WorkItemRepository>.value(value: repo),
          RepositoryProvider<WorkItemFormRepository>.value(value: forms),
          RepositoryProvider<WriteQueue>.value(value: queue),
          RepositoryProvider<AuthService>.value(value: authService),
          RepositoryProvider<PullRequestRepository>.value(value: prs),
          ...mentionProviders(stubs),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            theme: BoardhopTheme.light(),
            home: AccountScope(
              accountId: 'u1',
              child: WorkItemDetailPage(
                org: 'o',
                project: 'p',
                id: 15545,
                initialTab: tab,
                initialCommentId: commentId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The tab body's own scroller, not the `TabBarView`'s page view.
  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .pixels;

  /// Which tab the strip has selected.
  String selectedTab(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index.toString();

  /// The one comment card wearing the tint, by its place in the list.
  int? highlightedIndex(WidgetTester tester) {
    final cards = tester.widgetList<AnchorHighlight>(
      find.byType(AnchorHighlight, skipOffstage: false),
    );
    var index = 0;
    for (final card in cards) {
      if (card.active) return index;
      index++;
    }
    return null;
  }

  testWidgets('?comment={id} opens the Comments tab, scrolls to that comment '
      'and tints it for two seconds', (tester) async {
    await pump(tester, commentId: 2010);

    // The comments have a tab of their own now, so the anchor has to get
    // there before it can scroll.
    expect(selectedTab(tester), '2');
    // And then it scrolled down the discussion to reach the comment.
    expect(scrollOffset(tester), greaterThan(0));

    // The comment the push named is on screen, and it is the tinted one.
    expect(highlightedIndex(tester), isNotNull);
    final highlighted = find
        .byWidgetPredicate((w) => w is AnchorHighlight && w.active)
        .first;
    expect(
      find.descendant(
        of: highlighted,
        // The comment body is rendered HTML, so it is a RichText.
        matching: find.textContaining('comment 10', findRichText: true),
      ),
      findsOneWidget,
    );
    final box = tester.getRect(highlighted);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(box.top, lessThan(screen.height), reason: 'scrolled into view');
    expect(box.bottom, greaterThan(0));

    // The tint fades after about two seconds; nothing else changes.
    await tester.pump(kAnchorHighlight);
    await tester.pumpAndSettle();
    expect(highlightedIndex(tester), isNull);
  });

  testWidgets('a comment id that is not in the list tints nothing and shows '
      'no error', (tester) async {
    await pump(tester, commentId: 999999);
    expect(highlightedIndex(tester), isNull);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    // The tab is still the one the push asked for, at the top of the list,
    // and its badge counts what is there.
    expect(selectedTab(tester), '2');
    expect(scrollOffset(tester), 0);
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('$comments'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without an anchor the page opens at the top as before', (
    tester,
  ) async {
    await pump(tester);
    expect(selectedTab(tester), '0');
    expect(highlightedIndex(tester), isNull);
    expect(scrollOffset(tester), 0);
    expect(find.text('Anchor the pushed comment'), findsOneWidget);
    // Details has no composer; the comments are a tab away.
    expect(find.byTooltip('Post comment'), findsNothing);
  });

  /// The row inside the mention list, so a name that is also on a comment
  /// card is not ambiguous.
  Finder pickerRow(String name) => find.descendant(
    of: find.byKey(const Key('mentionOptions')),
    matching: find.text(name),
  );

  testWidgets('a picked mention is posted as @<guid>, and queued that way '
      'when the post cannot go', (tester) async {
    // The composer lives on the Comments tab, which is where a comment is
    // written.
    await pump(tester, tab: 'comments');
    when(() => repo.addComment('o', 'p', 15545, any())).thenAnswer(
      (_) async => WorkItemComment(
        id: 3000,
        text: 'posted',
        renderedText: '<p>posted</p>',
        createdBy: kelly,
        createdDate: DateTime.utc(2026, 9, 14),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ping @kel');
    await tester.pumpAndSettle();
    await tester.tap(pickerRow('Kelly Kamm'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    // The wire form, not what the composer drew.
    verify(() => repo.addComment('o', 'p', 15545, 'ping @<$kellyGuid>'))
        .called(1);

    // Offline, the queue stores the comment as a plain string, so it has to
    // already carry the GUID (research/16 M13).
    when(() => repo.addComment('o', 'p', 15545, any()))
        .thenThrow(const AdoNetworkException('offline'));
    when(
      () => queue.enqueueComment(
        org: any(named: 'org'),
        project: any(named: 'project'),
        id: any(named: 'id'),
        text: any(named: 'text'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async {});

    await tester.enterText(find.byType(TextField), 'again @kel');
    await tester.pumpAndSettle();
    await tester.tap(pickerRow('Kelly Kamm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    verify(
      () => queue.enqueueComment(
        org: 'o',
        project: 'p',
        id: 15545,
        text: 'again @<$kellyGuid>',
        description: any(named: 'description'),
      ),
    ).called(1);
  });

  /// research/17 T6: attachments need a connection. A comment written with
  /// files while the connection is gone still queues — as text — and the
  /// snackbar says which files did not go with it.
  testWidgets('offline, a comment with files queues the text alone and says '
      'what was left out', (tester) async {
    await pump(tester, tab: 'comments');
    final bytes = Uint8List.fromList(const [1, 2, 3, 4]);
    when(() => forms.uploadAttachment('o', 'p', any(), any()))
        .thenThrow(const AdoNetworkException('offline'));
    when(() => repo.addComment('o', 'p', 15545, any()))
        .thenThrow(const AdoNetworkException('offline'));
    when(
      () => queue.enqueueComment(
        org: any(named: 'org'),
        project: any(named: 'project'),
        id: any(named: 'id'),
        text: any(named: 'text'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async {});

    // Two files, through the Android keyboard rather than the platform
    // picker: the page builds the composer itself, so there is nothing to
    // inject here (T10 is the same seam).
    final insert = tester
        .widget<TextField>(find.byType(TextField))
        .contentInsertionConfiguration!;
    for (var i = 0; i < 2; i++) {
      insert.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://x/$i',
          data: bytes,
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byType(InputChip), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'still worth saying');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();

    // The text alone is what is queued — no attachment markup.
    verify(
      () => queue.enqueueComment(
        org: 'o',
        project: 'p',
        id: 15545,
        text: 'still worth saying',
        description: any(named: 'description'),
      ),
    ).called(1);
    expect(
      find.text('Offline: the comment will post later, without the 2 files.'),
      findsOneWidget,
    );
    // And now that the page knows it is offline, nothing more can be
    // attached until the connection is back (T6).
    expect(find.byTooltip('Attachments need a connection'), findsOneWidget);
  });
}
