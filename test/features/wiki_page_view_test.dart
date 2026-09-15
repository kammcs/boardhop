import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/data/repositories/wiki_repository.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/mention/mention_markdown.dart';
import 'package:boardhop/features/wiki/widgets/wiki_find.dart';
import 'package:boardhop/features/wiki/widgets/wiki_markdown.dart';
import 'package:boardhop/features/wiki/widgets/wiki_page_view.dart';
import 'package:boardhop/features/wiki/widgets/wiki_source_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Wikis extends Mock implements WikiRepository {}

class _AuthService extends Mock implements AuthService {}

/// The wiki reader (research/20 K9, W-B): its chrome, its footer, where a
/// link goes, and the two rules the markdown seam has to keep.
void main() {
  const org = 'o';
  const project = 'p';
  const wikiId = 'wiki-1';
  const path = '/Boardhop/Links';

  const phone = Size(1170, 2532);

  const wiki = Wiki(
    id: wikiId,
    name: 'DevOps-Mobile-App.wiki',
    type: WikiType.projectWiki,
    versions: ['wikiMaster'],
  );

  const content = '''
# Links

Text with a [child](./Deep child), an [anchor](#tables) and a
[page](/Boardhop/Constructs).

## Tables

A table.

### Deeper

More.
''';

  late _Wikis wikis;
  late _AuthService auth;
  late List<String> visited;

  WikiPageNode tree() => WikiPageNode.fromJson({
    'path': '/',
    'isParentPage': true,
    'subPages': [
      {
        'path': '/Boardhop',
        'id': 236,
        'isParentPage': true,
        'subPages': [
          {'path': '/Boardhop/Links', 'id': 240, 'isParentPage': true},
        ],
      },
    ],
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    wikis = _Wikis();
    auth = _AuthService();
    visited = [];

    when(() => auth.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'token');
    when(
      () => wikis.cachedPage(
        org,
        project,
        any(),
        path: any(named: 'path'),
        id: any(named: 'id'),
        version: any(named: 'version'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => wikis.page(
        org,
        project,
        any(),
        path: any(named: 'path'),
        id: any(named: 'id'),
        version: any(named: 'version'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer(
      (_) async => const WikiPage(
        path: path,
        id: 240,
        gitItemPath: '/Boardhop/Links.md',
        content: content,
      ),
    );
    when(
      () =>
          wikis.cachedTree(org, project, any(), version: any(named: 'version')),
    ).thenAnswer((_) async => tree());
    when(
      () => wikis.lastChange(
        org,
        project,
        any(),
        any(),
        version: any(named: 'version'),
      ),
    ).thenAnswer(
      (_) async => WikiPageChange(
        author: 'Kelly Kamm',
        date: DateTime.utc(2026, 9, 15, 12),
      ),
    );
    when(() => wikis.attachmentUri(org, project, any(), any()))
        .thenReturn(Uri.parse('https://dev.azure.com/items?path=x'));
  });

  setUpAll(() => registerFallbackValue(wiki));

  Future<void> pump(
    WidgetTester tester, {
    bool embedded = false,
    void Function(String path, {String? anchor})? onOpenPage,
    Size size = phone,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/wiki-page/$wikiId',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/wiki-page/:wiki',
          builder: (context, state) => AccountScope(
            accountId: 'u1',
            child: WikiPageView(
              org: org,
              project: project,
              wiki: wiki,
              path: path,
              embedded: embedded,
              onOpenPage: onOpenPage,
            ),
          ),
        ),
        for (final route in [
          '/a/:account/orgs/:org/projects/:project/work-item/:id',
          '/a/:account/orgs/:org/projects/:project/work-items/:id',
          '/a/:account/orgs/:org/pull-requests/:id',
        ])
          GoRoute(
            path: route,
            builder: (context, state) {
              visited.add(state.uri.toString());
              return const Scaffold(body: Text('elsewhere'));
            },
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WikiRepository>.value(value: wikis),
          RepositoryProvider<AuthService>.value(value: auth),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp.router(
            theme: BoardhopTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The reader's own link handler, reached the way a tap reaches it.
  void tapLink(WidgetTester tester, String href) {
    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody).first);
    body.onTapLink!('text', href, '');
  }

  group('find in page', () {
    testWidgets('the bar opens in the app bar, counts and closes', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(WikiFindBar), findsNothing);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // In the app bar's own bottom, which the keyboard can never cover —
      // the reader is a page over the shell and a bottom-anchored bar would
      // have to spend `viewInsets` itself (K4).
      expect(find.byType(WikiFindBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(WikiFindBar),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'table');
      // The field is debounced, and the count is only known once the body
      // has rebuilt with the new syntax.
      await tester.pump(
        WikiFindBar.debounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Close find'));
      await tester.pumpAndSettle();
      expect(find.byType(WikiFindBar), findsNothing);
    });

    testWidgets('a term nobody matches says so rather than going quiet', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nothinghere');
      await tester.pump(
        WikiFindBar.debounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });
  });

  group('chrome', () {
    testWidgets('the title, the parent path and the footer', (tester) async {
      await pump(tester);

      expect(find.text('Links'), findsWidgets);
      // The breadcrumb comes off the cached tree, never a call of its own.
      expect(find.text('Boardhop'), findsOneWidget);
      expect(
        find.textContaining('Last changed by Kelly Kamm on 15 Sep 2026'),
        findsOneWidget,
      );
      expect(find.text('Edit on the web'), findsOneWidget);
    });

    testWidgets('the footer stays hidden while the change is unknown', (
      tester,
    ) async {
      when(
        () => wikis.lastChange(
          org,
          project,
          any(),
          any(),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async => null);

      await pump(tester);

      expect(find.text('Edit on the web'), findsNothing);
    });

    testWidgets('the contents sheet lists h1–h3 and nothing deeper', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.toc));
      await tester.pumpAndSettle();

      expect(find.text('Contents'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Tables'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Deeper'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Copy link puts the id form on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pump(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();

      expect(
        copied,
        'https://dev.azure.com/o/p/_wiki/wikis/'
        'DevOps-Mobile-App.wiki/240/Links',
      );
    });

    testWidgets('Show source opens the raw markdown', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show source'));
      await tester.pumpAndSettle();

      expect(find.byType(WikiSourcePage), findsOneWidget);
      expect(find.textContaining('## Tables'), findsOneWidget);
    });

    testWidgets('the overflow offers Open on web', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      expect(find.text('Open on web'), findsOneWidget);
    });
  });

  group('what a page read records', () {
    testWidgets('the last path and a recent, per wiki (K1, K11)', (
      tester,
    ) async {
      await pump(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wiki_last_path:$org/$project/$wikiId'), path);
      expect(
        prefs.getString('wiki_recents:$org/$project/$wikiId'),
        contains('"path":"/Boardhop/Links"'),
      );
    });
  });

  group('links', () {
    testWidgets('a wiki-relative href pushes another reader', (tester) async {
      await pump(tester);
      final router = GoRouter.of(
        tester.element(find.byType(WikiPageView).first),
      );

      // `./x` is a **sibling** of the page, not a child: the page
      // `/Boardhop/Links` is the file `/Boardhop/Links.md`, so its folder
      // is `/Boardhop` (W-A, research/20 §4.1).
      tapLink(tester, './Deep child');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        contains('wiki-page/$wikiId?path=%2FBoardhop%2FDeep+child'),
      );

      tapLink(tester, 'Links/Deep child#tables');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        contains(
          'wiki-page/$wikiId?path=%2FBoardhop%2FLinks%2FDeep+child'
          '&anchor=tables',
        ),
      );
    });

    testWidgets('a same-wiki web URL opens in the reader too (K5)', (
      tester,
    ) async {
      String? opened;
      await pump(
        tester,
        embedded: true,
        onOpenPage: (p, {anchor}) => opened = p,
      );

      tapLink(
        tester,
        'https://dev.azure.com/o/p/_wiki/wikis/$wikiId'
        '?pagePath=%2FBoardhop%2FConstructs',
      );
      await tester.pumpAndSettle();

      expect(opened, '/Boardhop/Constructs');
    });

    testWidgets('an embedded reader selects instead of pushing', (
      tester,
    ) async {
      final opened = <String>[];
      await pump(
        tester,
        embedded: true,
        onOpenPage: (p, {anchor}) => opened.add(p),
      );

      tapLink(tester, '/Boardhop/Constructs');
      await tester.pumpAndSettle();

      expect(opened, ['/Boardhop/Constructs']);
      // No back arrow in a pane: the tree is beside it (K6).
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('#anchor scrolls and navigates nowhere', (tester) async {
      await pump(tester);
      final router = GoRouter.of(
        tester.element(find.byType(WikiPageView).first),
      );
      final before = router.state.uri.toString();

      tapLink(tester, '#tables');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), before);
      expect(visited, isEmpty);
    });

    testWidgets('#123 opens the work item and !456 the pull request', (
      tester,
    ) async {
      await pump(tester);

      tapLink(tester, MentionHref.of(MentionKind.workItem, '15545'));
      await tester.pumpAndSettle();
      expect(visited.single, contains('/work-item/15545'));

      // Back to the reader, then the pull request.
      GoRouter.of(tester.element(find.text('elsewhere'))).pop();
      await tester.pumpAndSettle();
      tapLink(tester, MentionHref.of(MentionKind.pullRequest, '8334'));
      await tester.pumpAndSettle();
      expect(visited.last, contains('/pull-requests/8334'));
    });

    testWidgets('an embedded reader keeps the dock for a work item', (
      tester,
    ) async {
      await pump(tester, embedded: true);

      tapLink(tester, MentionHref.of(MentionKind.workItem, '15545'));
      await tester.pumpAndSettle();

      // The branch route, not the standalone one (see Routes docs).
      expect(visited.single, contains('/work-items/15545'));
    });
  });

  group('the markdown seam', () {
    testWidgets('the body is never selectable, a SelectionArea is', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(SelectionArea), findsWidgets);
      for (final body in tester.widgetList<MarkdownBody>(
        find.byType(MarkdownBody),
      )) {
        expect(
          body.selectable,
          isFalse,
          reason: 'selectable: true measured ~7x slower (W-A spike)',
        );
      }
    });

    test('the split cuts at headings and respects fences', () {
      final sections = WikiMarkdown.split('''
Intro.

# One

text

```
# not a heading
```

## Two ##

more
''');

      expect(sections.first.heading, isNull);
      expect(sections.map((s) => s.heading?.text).toList(), [
        null,
        'One',
        'Two',
      ]);
      expect(sections[1].markdown, contains('# not a heading'));
      expect(sections.last.heading!.anchor, 'two');
      expect(sections[1].heading!.key, isNotNull);
    });

    test('the registry offers contents from two headings up', () {
      final headings = WikiHeadings();
      addTearDown(headings.dispose);

      headings.reset([WikiHeading(level: 1, text: 'One', anchor: 'one')]);
      expect(headings.hasContents, isFalse);

      headings.reset([
        WikiHeading(level: 1, text: 'One', anchor: 'one'),
        WikiHeading(level: 2, text: 'Two', anchor: 'two'),
        WikiHeading(level: 4, text: 'Deep', anchor: 'deep'),
      ]);
      expect(headings.hasContents, isTrue);
      expect(headings.contents.map((h) => h.text), ['One', 'Two']);
      expect(headings.find('two')?.text, 'Two');
    });
  });
}
