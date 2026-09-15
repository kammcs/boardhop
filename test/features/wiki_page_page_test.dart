import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/data/repositories/wiki_repository.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/wiki/wiki_page_page.dart';
import 'package:boardhop/features/wiki/widgets/wiki_page_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Wikis extends Mock implements WikiRepository {}

class _AuthService extends Mock implements AuthService {}

/// The standalone reader route: all it adds to [WikiPageView] is finding the
/// wiki the route names (research/20 §4.3).
void main() {
  const org = 'o';
  const project = 'p';
  const codeWikiId = 'w-code';

  const projectWiki = Wiki(
    id: 'wiki-1',
    name: 'DevOps-Mobile-App.wiki',
    type: WikiType.projectWiki,
    versions: ['wikiMaster'],
  );

  const codeWiki = Wiki(
    id: codeWikiId,
    name: 'Boardhop docs',
    type: WikiType.codeWiki,
    repositoryId: 'repo-1',
    mappedPath: '/docs',
    versions: ['wiki-docs', 'wiki-docs-v2'],
  );

  late _Wikis wikis;
  late _AuthService auth;

  setUpAll(() => registerFallbackValue(projectWiki));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    wikis = _Wikis();
    auth = _AuthService();

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
        path: '/Home',
        id: 252,
        gitItemPath: '/docs/Home.md',
        content: '# Boardhop docs\n\nText.',
      ),
    );
    when(
      () =>
          wikis.cachedTree(org, project, any(), version: any(named: 'version')),
    ).thenAnswer((_) async => null);
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
    ).thenReturn(Uri.parse('https://dev.azure.com/items?path=x'));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/page',
      routes: [
        GoRoute(
          path: '/page',
          builder: (context, state) => const AccountScope(
            accountId: 'u1',
            child: WikiPagePage(
              org: org,
              project: project,
              wikiIdOrName: codeWikiId,
              path: '/Home',
              version: 'wiki-docs',
            ),
          ),
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

  testWidgets('a wiki the cached list does not name is read again first', (
    tester,
  ) async {
    // The list is kept for a day. A code wiki published since — which is
    // exactly what a search hit or a pasted link points at — was reported
    // as "not in p any more" until the page asked for a fresh list
    // (found on the iPhone, spike w38).
    when(() => wikis.cachedWikis(org, project))
        .thenAnswer((_) async => const [projectWiki]);
    when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
        .thenAnswer(
          (invocation) async => invocation.namedArguments[#refresh] == true
              ? const [projectWiki, codeWiki]
              : const [projectWiki],
        );

    await pump(tester);

    expect(find.byType(WikiPageView), findsOneWidget);
    expect(find.textContaining('any more'), findsNothing);
    verify(() => wikis.wikis(org, project, refresh: true)).called(1);
  });

  testWidgets('a wiki no list names is still reported as gone', (tester) async {
    when(() => wikis.cachedWikis(org, project)).thenAnswer((_) async => null);
    when(() => wikis.wikis(org, project, refresh: any(named: 'refresh')))
        .thenAnswer((_) async => const [projectWiki]);

    await pump(tester);

    expect(find.textContaining('any more'), findsOneWidget);
  });

  testWidgets('a wiki the cache already names costs no call', (tester) async {
    when(() => wikis.cachedWikis(org, project))
        .thenAnswer((_) async => const [projectWiki, codeWiki]);

    await pump(tester);

    expect(find.byType(WikiPageView), findsOneWidget);
    verifyNever(
      () => wikis.wikis(org, project, refresh: any(named: 'refresh')),
    );
  });
}
