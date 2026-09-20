import 'dart:typed_data';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/widgets/tab_count_badge.dart';
import 'package:boardhop/features/work_items/form/controls/attachments_section.dart';
import 'package:boardhop/features/work_items/work_item_detail_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class _Repo extends Mock implements WorkItemRepository {}

class _Forms extends Mock implements WorkItemFormRepository {}

class _Queue extends Mock implements WriteQueue {}

class _AuthService extends Mock implements AuthService {}

/// Kelly, 2026-09-14: "split work items into three tabs — the detail,
/// related, and comments. Related and comments can have numbered badges."
/// This is what the split has to keep true.
void main() {
  const org = 'https://dev.azure.com/o/_apis/wit/workItems';
  const attachment =
      'https://dev.azure.com/o/_apis/wit/attachments/'
      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  /// A 1x1 transparent GIF: enough for `Image.memory` to decode.
  final pixel = Uint8List.fromList([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, //
    0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44,
    0x01, 0x00, 0x3B,
  ]);

  WorkItem itemWith({
    List<WorkItemRelation> relations = const [],
    String title = 'Three tabs for a long item',
  }) => WorkItem(
    id: 15545,
    rev: 3,
    fields: {
      'System.WorkItemType': 'Task',
      'System.Title': title,
      'System.State': 'Active',
      'System.AreaPath': 'Scratch',
      'System.IterationPath': 'Scratch',
      'System.Description': '<p>The description on the Details tab</p>',
    },
    multilineFieldsFormat: const {'System.Description': 'html'},
    relations: relations,
  );

  const links = [
    WorkItemRelation(rel: WorkItemRelation.childRel, url: '$org/15546'),
    WorkItemRelation(rel: WorkItemRelation.relatedRel, url: '$org/15547'),
  ];

  /// The listed file in most of these tests is text rather than an image:
  /// an image row draws an [AttachmentImage] thumbnail, whose decode never
  /// finishes under `pumpAndSettle` in a widget test.
  const file = WorkItemRelation(
    rel: WorkItemRelation.attachedFileRel,
    url: attachment,
    attributes: {'name': 'notes.txt', 'resourceSize': 2048},
  );

  const image = WorkItemRelation(
    rel: WorkItemRelation.attachedFileRel,
    url: attachment,
    attributes: {'name': 'screenshot.png', 'resourceSize': 2048},
  );

  late _Repo repo;
  late _Forms forms;
  late _Queue queue;
  late MentionStubs stubs;
  late MentionPullRequests prs;
  late List<String> fetched;

  void stubItem(WorkItem item, {int comments = 3}) {
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
            createdBy: const IdentityRef(
              displayName: 'Ada Example',
              uniqueName: 'ada@example.test',
              id: 'ada-id',
            ),
            createdDate: DateTime.utc(2026, 9, 13, 10, i),
          ),
      ],
    );
  }

  setUp(() {
    repo = _Repo();
    forms = _Forms();
    queue = _Queue();
    fetched = [];
    stubs = mentionStubs();
    prs = MentionPullRequests();
    stubMentionPullRequests(prs);
    when(() => forms.projectId('o', 'p')).thenAnswer((_) async => 'proj');
    when(() => forms.defaultTeamId('o', 'p')).thenAnswer((_) async => 'team');
    when(() => forms.attachmentBytes(any())).thenAnswer((invocation) async {
      fetched.add(invocation.positionalArguments.first as String);
      return pixel;
    });
    when(() => repo.watchList('o', 'p', any()))
        .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
    when(() => stubs.people.teamMembers('o', 'proj', 'team'))
        .thenAnswer((_) async => const []);
    when(() => repo.types('o', 'p')).thenAnswer(
      (_) async => const [
        WorkItemType(name: 'Task', referenceName: 'Microsoft.VSTS.Task'),
      ],
    );
    when(() => repo.batch('o', 'p', any())).thenAnswer(
      (_) async => [
        WorkItem(
          id: 15546,
          rev: 1,
          fields: const {
            'System.WorkItemType': 'Task',
            'System.Title': 'The child task',
            'System.State': 'New',
          },
        ),
        WorkItem(
          id: 15547,
          rev: 1,
          fields: const {
            'System.WorkItemType': 'Task',
            'System.Title': 'The related task',
            'System.State': 'New',
          },
        ),
      ],
    );
    when(() => forms.formSpec('o', 'p', 'Task'))
        .thenThrow(const AdoForbiddenException('no spec here'));
    when(() => forms.backlogTypes('o', 'p'))
        .thenThrow(const AdoForbiddenException('no backlog here'));
    stubItem(itemWith(relations: [...links, file]));
  });

  Future<void> pump(
    WidgetTester tester, {
    String? tab,
    Size size = const Size(1200, 2400),
    double devicePixelRatio = 3,
    double textScale = 1,
    bool embedded = false,
    bool settle = true,
    double rightPadding = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.padding = FakeViewPadding(
      right: rightPadding * devicePixelRatio,
    );
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: AccountScope(
              accountId: 'u1',
              child: WorkItemDetailPage(
                org: 'o',
                project: 'p',
                id: 15545,
                initialTab: tab,
                embedded: embedded,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    // A thumbnail keeps a frame pending for ever in a widget test, so the
    // frames are pumped by hand instead.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  TabController controller(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!;

  Finder badge(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Tab)),
    matching: find.byType(TabCountBadge),
  );

  String? badgeText(WidgetTester tester, String label) {
    final texts = tester.widgetList<Text>(
      find.descendant(of: badge(label), matching: find.byType(Text)),
    );
    return texts.isEmpty ? null : texts.first.data;
  }

  testWidgets('three tabs, with counts on Related and Comments', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(Tab), findsNWidgets(3));
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Related'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);

    // Two links plus one file, and three comments.
    expect(badgeText(tester, 'Related'), '3');
    expect(badgeText(tester, 'Comments'), '3');

    // Details is what opens, and it holds the header and the fields.
    expect(controller(tester).index, 0);
    expect(find.text('Three tabs for a long item'), findsOneWidget);
    expect(find.text('Area'), findsOneWidget);
    expect(
      find.textContaining(
        'The description on the Details tab',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // Nothing from the other two tabs is on it.
    expect(find.textContaining('The child task'), findsNothing);
    expect(find.textContaining('comment 1', findRichText: true), findsNothing);
  });

  testWidgets('research/20 K5: a Wiki Page link and a hyperlink are on '
      'Related and counted', (tester) async {
    const wiki = WorkItemRelation(
      rel: WorkItemRelation.artifactLinkRel,
      url:
          'vstfs:///Wiki/WikiPage/98720989-1111-2222-3333-444455556666%2F'
          '2bd59283-17a5-4fd0-b964-cd9a4189f721%2FBoardhop%2FConstructs',
      attributes: {'name': 'Wiki Page'},
    );
    const hyperlink = WorkItemRelation(
      rel: WorkItemRelation.hyperlinkRel,
      url: 'https://example.test/spec/v2',
    );
    const git = WorkItemRelation(
      rel: WorkItemRelation.artifactLinkRel,
      url: 'vstfs:///Git/PullRequestId/1/2/8334',
    );
    stubItem(itemWith(relations: [...links, file, wiki, hyperlink, git]));
    await pump(tester);

    // The two work item links, the wiki page and the hyperlink, plus the
    // one file; the Git artifact link is Azure DevOps's own Development
    // group and is not listed.
    expect(badgeText(tester, 'Related'), '5');

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    expect(find.text('Wiki page'), findsOneWidget);
    expect(find.text('Constructs'), findsOneWidget);
    expect(find.text('/Boardhop/Constructs'), findsOneWidget);
    expect(find.text('example.test/spec/v2'), findsOneWidget);
    expect(find.textContaining('8334'), findsNothing);
  });

  testWidgets('a count of zero draws no badge at all', (tester) async {
    stubItem(itemWith(), comments: 0);
    await pump(tester);

    expect(badgeText(tester, 'Related'), isNull);
    expect(badgeText(tester, 'Comments'), isNull);

    // And the empty Related tab says so in one quiet line.
    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing linked yet'), findsOneWidget);
  });

  testWidgets('the composer is on Comments and nowhere else', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Post comment'), findsNothing);

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Post comment'), findsNothing);

    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Post comment'), findsOneWidget);
    expect(find.textContaining('comment 1', findRichText: true), findsWidgets);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Post comment'), findsNothing);
  });

  testWidgets('?tab=related opens Related, ?tab=comments opens Comments', (
    tester,
  ) async {
    await pump(tester, tab: 'related');
    expect(controller(tester).index, 1);
    expect(find.textContaining('The child task'), findsOneWidget);
    expect(find.textContaining('The related task'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    // The size the relation carries, under the name.
    expect(find.text('2 KB'), findsOneWidget);

    await pump(tester, tab: 'comments');
    expect(controller(tester).index, 2);

    // Anything else is Details, as a link with no tab is.
    await pump(tester, tab: 'nonsense');
    expect(controller(tester).index, 0);
  });

  testWidgets('switching tabs neither refetches nor forgets the tab', (
    tester,
  ) async {
    await pump(tester);
    verify(() => repo.refreshItem('o', 'p', 15545)).called(1);

    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    verifyNever(() => repo.refreshItem('o', 'p', 15545));

    // A rebuild from the drift stream leaves the reader where they were.
    await tester.pump();
    expect(controller(tester).index, 1);

    // And a pull to refresh on this tab refreshes without moving it.
    await tester.fling(
      find.textContaining('The child task'),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();
    verify(() => repo.refreshItem('o', 'p', 15545)).called(1);
    expect(controller(tester).index, 1);
  });

  testWidgets('an attachment row opens through the shared open path', (
    tester,
  ) async {
    await pump(tester, tab: 'related');
    // Listing the files fetches nothing; only opening one does.
    expect(fetched, isEmpty);

    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();

    // `openAttachment` — the form's Attachments page calls the same
    // function — fetched the bytes through `AttachmentSource.bytes` once,
    // rather than the tab repeating the fetch of its own.
    expect(fetched, [attachment]);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('an image attachment opens the full-screen viewer', (
    tester,
  ) async {
    stubItem(itemWith(relations: const [image]));
    await pump(tester, tab: 'related', settle: false);

    expect(find.text('screenshot.png'), findsOneWidget);
    await tester.tap(find.text('screenshot.png'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The same viewer the form's Attachments page opens, over the root
    // navigator so the shell's chrome is not left on top of the image.
    expect(find.byType(AttachmentViewer), findsOneWidget);
    expect(find.text('screenshot.png'), findsWidgets);
  });

  testWidgets('at xxxL the strip scrolls and every label stays whole', (
    tester,
  ) async {
    const phone = Size(400, 1400);
    double labelWidth(String label) => tester.getSize(find.text(label)).width;

    // What the three labels want when there is room to spare.
    await pump(tester, size: const Size(1200, 1400), devicePixelRatio: 1);
    final natural = {
      for (final l in ['Details', 'Related', 'Comments']) l: labelWidth(l),
    };

    // With room to spare the strip divides it evenly.
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);

    // At phone width every label is still laid out whole — the strip
    // scrolls rather than squeezing one of them.
    await pump(tester, size: phone, devicePixelRatio: 1);
    final ordinary = {for (final l in natural.keys) l: labelWidth(l)};
    for (final label in natural.keys) {
      expect(ordinary[label], closeTo(natural[label]!, 0.5), reason: label);
    }

    await pump(tester, size: phone, devicePixelRatio: 1, textScale: 3.1);

    // Three filled thirds would clip these; the strip scrolls instead.
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    for (final label in ordinary.keys) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(
        labelWidth(label),
        greaterThan(natural[label]! * 2.5),
        reason: '$label was squeezed rather than laid out at 3.1x',
      );
    }
    // The badges came with them.
    expect(badgeText(tester, 'Related'), '3');
    expect(badgeText(tester, 'Comments'), '3');

    // Every tab body at this size as well; a RenderFlex overflow anywhere
    // fails the test on its own.
    for (final index in [1, 2, 0]) {
      controller(tester).animateTo(index);
      await tester.pumpAndSettle();
      expect(controller(tester).index, index);
    }
  });

  testWidgets('the embedded pane at the expanded breakpoint keeps the tabs', (
    tester,
  ) async {
    await pump(
      tester,
      embedded: true,
      size: const Size(1600, 1000),
      devicePixelRatio: 2,
    );

    // No back button in the pane, but the same three tabs.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(Tab), findsNWidgets(3));
    expect(find.text('#15545'), findsOneWidget);

    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Post comment'), findsOneWidget);
    expect(controller(tester).index, 2);
  });

  /// The standalone route is pushed over the project shell, so nothing
  /// above it spends the display's side insets. On the iPhone Duo's cover
  /// that is the 84 pt column the stacked status bar sits in, and the
  /// comments ran under it (research/23 §9.13). The embedded pane is inside
  /// the shell's own SafeArea and must not be inset a second time.
  testWidgets('the standalone route clears the display\'s side inset', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(1398, 2034),
      rightPadding: 84,
      settle: false,
    );

    expect(tester.getRect(find.byType(TabBarView)).right, closeTo(382, 0.5));
  });

  testWidgets('the embedded pane is not inset twice', (tester) async {
    await pump(
      tester,
      size: const Size(1398, 2034),
      rightPadding: 84,
      embedded: true,
      settle: false,
    );

    expect(tester.getRect(find.byType(TabBarView)).right, closeTo(466, 0.5));
  });
}
