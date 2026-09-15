import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/data/repositories/wiki_repository.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/wiki/widgets/wiki_page_view.dart';
import 'package:boardhop/features/wiki/widgets/wiki_tree_view.dart';
import 'package:boardhop/features/wiki/wiki_tree_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Wikis extends Mock implements WikiRepository {}

class _AuthService extends Mock implements AuthService {}

/// The Wiki view (research/20 W-B): what it opens on, how the tree behaves,
/// and what the tablet does with the extra width.
void main() {
  const org = 'o';
  const project = 'p';
  const wikiId = 'wiki-1';
  const codeWikiId = 'wiki-2';

  const phone = Size(1170, 2532);
  const tablet = Size(2048, 1536);

  late _Wikis wikis;
  late _AuthService auth;
  late String location;
  late List<String> visited;

  const projectWiki = Wiki(
    id: wikiId,
    name: 'DevOps-Mobile-App.wiki',
    type: WikiType.projectWiki,
    versions: ['wikiMaster'],
  );

  const codeWiki = Wiki(
    id: codeWikiId,
    name: 'docs-wiki',
    type: WikiType.codeWiki,
    repositoryId: 'repo-1',
    mappedPath: '/docs',
    versions: ['main', 'release'],
  );

  /// The scratch wiki's own shape (research/20 §1), through `fromJson` so
  /// the model's own sibling ordering is what the page draws: the service
  /// answers siblings alphabetically and `.order` is what reorders them
  /// (spike w37).
  WikiPageNode tree() => WikiPageNode.fromJson({
    'path': '/',
    'isParentPage': true,
    'subPages': [
      {
        'path': '/Boardhop',
        'id': 236,
        'isParentPage': true,
        'subPages': [
          {'path': '/Boardhop/Constructs', 'id': 238, 'order': 1},
          {
            'path': '/Boardhop/Links',
            'id': 240,
            'order': 0,
            'isParentPage': true,
            'subPages': [
              {
                'path': '/Boardhop/Links/Deep child',
                'id': 242,
                'isParentPage': true,
                'subPages': [
                  {'path': '/Boardhop/Links/Deep child/Level 4', 'id': 246},
                ],
              },
              {'path': '/Boardhop/Links/Re-Order', 'id': 244, 'order': 1},
            ],
          },
          {
            'path': '/Boardhop/Pushed page',
            'order': 2,
            'isNonConformant': true,
          },
          {
            'path': '/Boardhop/Pushed tidy',
            'id': 249,
            'order': WikiPageNode.unordered,
          },
        ],
      },
    ],
  });

  WikiPage page(String path) => WikiPage(
    path: path,
    id: 240,
    gitItemPath: '$path.md',
    content: '# ${path.split('/').last}\n\nSome text.',
  );

  setUpAll(() {
    registerFallbackValue(projectWiki);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    wikis = _Wikis();
    auth = _AuthService();
    location = '';
    visited = [];

    when(() => auth.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'token');

    when(() => wikis.cachedWikis(org, project)).thenAnswer((_) async => null);
    when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
        .thenAnswer((_) async => const [projectWiki]);
    when(
      () =>
          wikis.cachedTree(org, project, any(), version: any(named: 'version')),
    ).thenAnswer((_) async => null);
    when(
      () => wikis.tree(
        org,
        project,
        any(),
        version: any(named: 'version'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => tree());
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
      (invocation) async =>
          page(invocation.namedArguments[#path] as String? ?? '/Boardhop'),
    );
    when(
      () => wikis.lastChange(
        org,
        project,
        any(),
        any(),
        version: any(named: 'version'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => wikis.attachmentUri(
        org,
        project,
        any(),
        any(),
        version: any(named: 'version'),
      ),
    ).thenReturn(Uri.parse('https://dev.azure.com/items'));
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = phone,
    double devicePixelRatio = 3,
    String query = '',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/wiki$query',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/wiki',
          builder: (context, state) {
            location = state.uri.toString();
            return AccountScope(
              accountId: 'u1',
              child: WikiTreePage(
                org: org,
                project: project,
                wikiIdOrName: state.uri.queryParameters['wiki'],
                path: state.uri.queryParameters['path'],
              ),
            );
          },
        ),
        for (final path in [
          '/a/:account/orgs/:org/projects/:project/wiki-page/:wiki',
          '/a/:account/orgs/:org/projects/:project/home',
          '/a/:account/orgs/:org/projects/:project/dashboards',
          '/a/:account/orgs/:org/projects',
        ])
          GoRoute(
            path: path,
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

  group('what the page opens on', () {
    testWidgets('a project with no wiki says so and offers the web', (
      tester,
    ) async {
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenAnswer((_) async => const <Wiki>[]);

      await pump(tester);

      expect(find.text('This project has no wiki'), findsOneWidget);
      expect(find.text('Open on web'), findsOneWidget);
    });

    testWidgets('one wiki draws its name, its type line and its tree', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester);

      expect(find.text('DevOps-Mobile-App.wiki'), findsOneWidget);
      expect(find.text('Project wiki'), findsOneWidget);
      expect(find.text('Boardhop'), findsOneWidget);
      // Expanded along the last path, so its children are on screen (K1).
      expect(find.text('Constructs'), findsOneWidget);
      expect(find.text('Links'), findsOneWidget);
      // One wiki: nothing to pick, so no chevron (K1).
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('the tree starts collapsed with no last path', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // A recent stops the first-visit home page from opening.
        'flutter.wiki_recents:$org/$project/$wikiId':
            '[{"path":"/Boardhop","title":"Boardhop"}]',
      });

      await pump(tester);

      expect(find.text('Boardhop'), findsWidgets);
      expect(find.text('Constructs'), findsNothing);
    });

    testWidgets('?wiki= wins over the remembered one', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_id:$org/$project': wikiId,
        'flutter.wiki_last_path:$org/$project/$codeWikiId': '/Boardhop',
      });
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenAnswer((_) async => const [projectWiki, codeWiki]);

      await pump(tester, query: '?wiki=$codeWikiId');

      expect(find.text('docs-wiki'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
    });
  });

  group('the branch pill (K8)', () {
    setUp(() {
      // A remembered path, so K1's first visit does not push the reader
      // over the tree and hide the app bar under test.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$codeWikiId': '/Boardhop',
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenAnswer((_) async => const [projectWiki, codeWiki]);
    });

    testWidgets('a phone shows the icon alone and keeps the wiki name', (
      tester,
    ) async {
      await pump(tester, query: '?wiki=$codeWikiId');

      // Beside the title the chip's label pushed the name out of the bar
      // altogether on the iPhone (spike w38), so on a phone the branch is
      // an icon action and the subtitle names it.
      expect(find.byKey(const Key('wikiBranchPill')), findsOneWidget);
      expect(find.text('docs-wiki'), findsOneWidget);
      // The branch alone: "Code wiki · main" ellipsises to "Code wiki · m…"
      // in the title column a phone leaves.
      expect(find.text('main'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'main'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tablet keeps the icon and the subtitle, no overflow', (
      tester,
    ) async {
      await pump(tester, size: tablet, query: '?wiki=$codeWikiId');

      // At the medium breakpoint the view switch carries its own labels and
      // leaves the title about 50 dp: a labelled chip overflows the bar.
      expect(find.byKey(const Key('wikiBranchPill')), findsOneWidget);
      expect(find.text('Code wiki · main'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'main'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a branch re-reads the tree at that version', (
      tester,
    ) async {
      await pump(tester, query: '?wiki=$codeWikiId');

      await tester.tap(find.byKey(const Key('wikiBranchPill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('release').last);
      await tester.pumpAndSettle();

      verify(
        () => wikis.tree(
          org,
          project,
          codeWikiId,
          version: 'release',
          refresh: any(named: 'refresh'),
        ),
      ).called(greaterThanOrEqualTo(1));
      expect(find.text('release'), findsOneWidget);
    });

    testWidgets('a project wiki has no branch pill', (tester) async {
      await pump(tester);

      expect(find.byKey(const Key('wikiBranchPill')), findsNothing);
      expect(find.text('Project wiki'), findsOneWidget);
    });
  });

  group('the tree', () {
    testWidgets('a chevron expands and collapses in place (K2)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_recents:$org/$project/$wikiId':
            '[{"path":"/Boardhop","title":"Boardhop"}]',
      });

      await pump(tester);
      expect(find.text('Constructs'), findsNothing);

      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      expect(find.text('Constructs'), findsOneWidget);
      expect(find.text('Pushed tidy'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();
      expect(find.text('Constructs'), findsNothing);
    });

    testWidgets('the non-conformant page is greyed and does not open', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester);

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Pushed page'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(
        find.text('Not readable: the file name has a space'),
        findsOneWidget,
      );

      await tester.tap(find.text('Pushed page'));
      await tester.pumpAndSettle();
      expect(visited, isEmpty);
    });

    testWidgets('sorting puts .order first and the rest behind it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester);

      final titles = tester
          .widgetList<WikiTreeTile>(find.byType(WikiTreeTile))
          .map((t) => t.row.node.title)
          .toList();
      expect(titles, [
        'Boardhop',
        'Links',
        'Constructs',
        'Pushed page',
        'Pushed tidy',
      ]);
    });

    testWidgets('a tap on a phone pushes the reader over the shell', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester);
      await tester.tap(find.text('Constructs'));
      await tester.pumpAndSettle();

      expect(
        visited.single,
        '/a/u1/orgs/$org/projects/$project/wiki-page/$wikiId'
        '?path=%2FBoardhop%2FConstructs',
      );
    });
  });

  group('recents and the first visit', () {
    testWidgets('the Recent strip lists what was read and opens it (K11)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
        'flutter.wiki_recents:$org/$project/$wikiId':
            '[{"path":"/Boardhop/Links","title":"Links"},'
            '{"path":"/Boardhop/Constructs","title":"Constructs"}]',
      });

      await pump(tester);

      expect(find.text('Recent'), findsOneWidget);
      expect(find.byType(WikiRecentsStrip), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(WikiRecentsStrip),
          matching: find.text('Links'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        visited.single,
        contains('wiki-page/$wikiId?path=%2FBoardhop%2FLinks'),
      );
    });

    testWidgets('the very first visit opens the home page (K1)', (
      tester,
    ) async {
      await pump(tester);

      expect(
        visited.single,
        '/a/u1/orgs/$org/projects/$project/wiki-page/$wikiId'
        '?path=%2FBoardhop',
      );
    });

    testWidgets('a remembered path is restored instead of the home page', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId':
            '/Boardhop/Links/Deep child',
      });

      await pump(tester);

      expect(visited, isEmpty);
      // Expanded along every ancestor of the remembered page.
      expect(find.text('Deep child'), findsOneWidget);
      expect(find.text('Level 4'), findsOneWidget);
    });
  });

  group('the picker', () {
    testWidgets('several wikis make the title a picker', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenAnswer((_) async => const [projectWiki, codeWiki]);

      await pump(tester);

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

      await tester.tap(find.text('DevOps-Mobile-App.wiki'));
      await tester.pumpAndSettle();

      expect(find.text('Wikis'), findsOneWidget);
      expect(find.text('Code wiki · main'), findsOneWidget);

      await tester.tap(find.text('docs-wiki'));
      await tester.pumpAndSettle();

      expect(location, contains('wiki=$codeWikiId'));
    });
  });

  group('the tablet', () {
    testWidgets('the tree keeps a pane and the page sits beside it (K6)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop/Links',
      });

      await pump(tester, size: tablet, devicePixelRatio: 2);

      expect(find.byType(WikiPageView), findsOneWidget);
      final view = tester.widget<WikiPageView>(find.byType(WikiPageView));
      expect(view.embedded, isTrue);
      expect(view.path, '/Boardhop/Links');
      expect(visited, isEmpty);
    });

    testWidgets('a tap selects in the pane and writes ?path=', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester, size: tablet, devicePixelRatio: 2);
      await tester.tap(find.text('Constructs'));
      await tester.pumpAndSettle();

      expect(visited, isEmpty);
      expect(location, contains('path=%2FBoardhop%2FConstructs'));
      final view = tester.widget<WikiPageView>(find.byType(WikiPageView));
      expect(view.path, '/Boardhop/Constructs');
    });
  });

  group('errors and offline', () {
    testWidgets('a wiki the sign-in cannot read is said inline', (
      tester,
    ) async {
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenThrow(const WikiUnavailable(statusCode: 401));

      await pump(tester);

      expect(find.textContaining('cannot read this project'), findsOneWidget);
      // Not the empty state: the wiki may well be there.
      expect(find.text('This project has no wiki'), findsNothing);
    });

    testWidgets('offline over a cached tree keeps the rows', (tester) async {
      when(() => wikis.cachedWikis(org, project))
          .thenAnswer((_) async => const [projectWiki]);
      when(
        () => wikis.cachedTree(
          org,
          project,
          any(),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async => tree());
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenThrow(const AdoNetworkException('No connection'));
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.wiki_last_path:$org/$project/$wikiId': '/Boardhop',
      });

      await pump(tester);

      expect(find.text('Boardhop'), findsOneWidget);
      expect(find.text('Constructs'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
    });

    testWidgets('another failure with nothing on screen is shown inline', (
      tester,
    ) async {
      when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
          .thenThrow(const AdoServerException('Boom'));

      await pump(tester);

      expect(find.text('Boom'), findsOneWidget);
    });
  });
}
