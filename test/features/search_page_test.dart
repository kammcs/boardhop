import 'dart:async';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/models/git_repository.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/search.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/search_repository.dart';
import 'package:boardhop/data/search_recents.dart';
import 'package:boardhop/features/search/search_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

AdoClient _client() => AdoClient(
  tokenProvider: ({String? tenantId, String? accountId}) async => 't',
);

/// What one search call was asked for.
typedef _Call = ({
  String? project,
  String text,
  List<String> types,
  List<String> states,
  int skip,
  SearchOrder order,
});

/// The real repository with its three searches replaced: every call is
/// recorded, the answer is whatever the test set for that term, and a gate
/// lets a test hold one answer back to see what the page does meanwhile.
class _FakeSearch extends SearchRepository {
  _FakeSearch() : super(_client(), PullRequestRepository(_client()));

  final workItemCalls = <_Call>[];
  final codeCalls = <_Call>[];
  final pullRequestCalls = <_Call>[];

  SearchResults<WorkItemSearchHit> Function(String text) workItems = (_) =>
      const SearchResults();
  CodeSearchResults Function(String text) code = (_) =>
      const CodeSearchResults(count: 0, hits: [], infoCode: 0);
  SearchResults<PullRequestSearchHit> Function(String text) pullRequests = (
    _,
  ) => const SearchResults();

  CachedSearch<SearchResults<WorkItemSearchHit>>? workItemsCached;
  SearchResults<PullRequestSearchHit>? pullRequestsCached;

  /// Thrown instead of answering, per kind.
  Object? workItemsThrows;
  Object? codeThrows;

  /// Terms whose live answer waits for the test to open the gate.
  final gates = <String, Completer<void>>{};

  Completer<void> gate(String term) => gates[term] = Completer<void>();

  Future<void> _wait(String term) async {
    final gate = gates[term];
    if (gate != null) await gate.future;
  }

  @override
  Future<SearchResults<WorkItemSearchHit>> searchWorkItems(
    String org, {
    String? project,
    required String text,
    List<String> types = const [],
    List<String> states = const [],
    int skip = 0,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    workItemCalls.add((
      project: project,
      text: text,
      types: types,
      states: states,
      skip: skip,
      order: order,
    ));
    await _wait(text.trim());
    final boom = workItemsThrows;
    if (boom != null) throw boom;
    return workItems(text.trim());
  }

  @override
  Future<CachedSearch<SearchResults<WorkItemSearchHit>>?> cachedWorkItems(
    String org, {
    String? project,
    required String text,
    List<String> types = const [],
    List<String> states = const [],
    int skip = 0,
    SearchOrder order = SearchOrder.relevance,
  }) async => workItemsCached;

  @override
  Future<CodeSearchResults> searchCode(
    String org, {
    String? project,
    required String text,
    String? repositoryName,
    int skip = 0,
  }) async {
    codeCalls.add((
      project: project,
      text: text,
      types: const [],
      states: const [],
      skip: skip,
      order: SearchOrder.relevance,
    ));
    await _wait(text.trim());
    final boom = codeThrows;
    if (boom != null) throw boom;
    return code(text.trim());
  }

  @override
  Future<CachedSearch<CodeSearchResults>?> cachedCode(
    String org, {
    String? project,
    required String text,
    String? repositoryName,
    int skip = 0,
  }) async => null;

  @override
  Future<SearchResults<PullRequestSearchHit>> searchPullRequests(
    String org, {
    String? project,
    required String text,
  }) async {
    pullRequestCalls.add((
      project: project,
      text: text,
      types: const [],
      states: const [],
      skip: 0,
      order: SearchOrder.relevance,
    ));
    await _wait(text.trim());
    return pullRequests(text.trim());
  }

  @override
  Future<SearchResults<PullRequestSearchHit>?> cachedPullRequests(
    String org, {
    String? project,
    required String text,
  }) async => pullRequestsCached;
}

/// Recents in memory, so no shared preferences plugin is needed.
class _FakeRecents extends SearchRecents {
  _FakeRecents({List<String>? stored})
    : entries = [...?stored],
      super(accountId: 'u1');

  final List<String> entries;

  @override
  Future<List<String>> list(String org) async => List.of(entries);

  @override
  Future<List<String>> add(String org, String text) async {
    entries
      ..removeWhere((e) => e.toLowerCase() == text.trim().toLowerCase())
      ..insert(0, text.trim());
    return List.of(entries);
  }

  @override
  Future<List<String>> remove(String org, String text) async {
    entries.removeWhere((e) => e.toLowerCase() == text.trim().toLowerCase());
    return List.of(entries);
  }

  @override
  Future<void> clear(String org) async => entries.clear();
}

WorkItemSearchHit workItemHit(
  int id, {
  String title = 'Board drag and drop',
  String type = 'Bug',
  String state = 'Active',
  String project = 'Scratch',
  String fragment = 'the <highlighthit>board</highlighthit> drags',
}) => WorkItemSearchHit(
  id: id,
  workItemType: type,
  title: title,
  state: state,
  projectName: project,
  projectId: 'p-$project',
  highlights: [SearchHighlight.parse('system.description', fragment)],
);

CodeSearchHit codeHit(String name) => CodeSearchHit(
  fileName: name,
  path: '/lib/$name',
  repositoryName: 'boardhop',
  repositoryId: 'r-1',
  projectName: 'Scratch',
  branch: 'main',
  contentMatches: 2,
);

PullRequestSearchHit prHit(int id, String title) => PullRequestSearchHit(
  pullRequest: PullRequest.fromJson({
    'pullRequestId': id,
    'title': title,
    'status': 'active',
    'sourceRefName': 'refs/heads/feature/x',
    'targetRefName': 'refs/heads/main',
    'creationDate': '2026-09-13T10:00:00Z',
    'createdBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
    'repository': {
      'id': 'r-1',
      'name': 'boardhop',
      'project': {'id': 'p-Scratch', 'name': 'Scratch'},
    },
  }),
  match: PrMatchField.title,
);

void main() {
  late _FakeSearch search;
  late _FakeRecents recents;
  late AuthBloc auth;

  setUp(() {
    search = _FakeSearch();
    recents = _FakeRecents();
    auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
  });

  Widget stub(String label) => Scaffold(
    appBar: AppBar(title: Text(label)),
    body: const SizedBox(),
  );

  Future<void> pump(
    WidgetTester tester, {
    String? q,
    SearchKind? kind,
    SearchScope scope = SearchScope.project,
    double textScale = 1,
    Size size = const Size(402, 874),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: Routes.search(
        'u1',
        'o',
        'Scratch',
        q: q,
        scope: scope.wire,
        kind: kind?.wire,
      ),
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/search',
          builder: (_, state) => SearchPage(
            org: state.pathParameters['org']!,
            project: state.pathParameters['project']!,
            initialQuery: state.uri.queryParameters['q'],
            scope: SearchScope.fromWire(state.uri.queryParameters['scope']),
            kind: SearchKind.fromWire(state.uri.queryParameters['kind']),
          ),
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/work-items/:id',
          builder: (_, state) => stub('item ${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/repos/:repo/file',
          builder: (_, state) =>
              stub('file ${state.uri.queryParameters['path']}'),
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/pull-requests/:id',
          builder: (_, state) => stub('pr ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SearchRepository>.value(value: search),
          RepositoryProvider<SearchRecents>.value(value: recents),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp.router(
            theme: brightness == Brightness.light
                ? BoardhopTheme.light()
                : BoardhopTheme.dark(),
            routerConfig: router,
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: AccountScope(accountId: 'u1', child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byType(TextField);

  group('decision D8: the trigger', () {
    testWidgets('nothing is sent under three characters', (tester) async {
      await pump(tester);
      await tester.enterText(field(), 'bo');
      await tester.pump(const Duration(seconds: 1));

      expect(search.workItemCalls, isEmpty);
      expect(search.codeCalls, isEmpty);
      expect(find.textContaining('at least 3'), findsOneWidget);
    });

    testWidgets('the sections wait out the debounce instead of reporting '
        'nothing found', (tester) async {
      await pump(tester);
      await tester.enterText(field(), 'board');
      await tester.pump(const Duration(milliseconds: 100));

      expect(search.workItemCalls, isEmpty, reason: 'still in the debounce');
      expect(find.text('No work items'), findsNothing);
      expect(find.text('No code results'), findsNothing);
      expect(find.text('No pull requests'), findsNothing);
      expect(find.textContaining('Searching Work items'), findsOneWidget);

      // Once the empty answer is really in, the sections say so.
      await tester.pumpAndSettle();
      expect(find.text('No work items'), findsOneWidget);
    });

    testWidgets('a See-all list says it is searching, not that it found '
        'nothing', (tester) async {
      await pump(tester, kind: SearchKind.workItems);
      await tester.enterText(field(), 'board');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('No work items for'), findsNothing);
      expect(find.textContaining('Searching Work items'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.textContaining('No work items for'), findsOneWidget);
    });

    testWidgets('a query goes 400 ms after the last keystroke, once', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(field(), 'boa');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(field(), 'boar');
      await tester.pump(const Duration(milliseconds: 399));
      expect(
        search.workItemCalls,
        isEmpty,
        reason: 'the second keystroke restarts the wait',
      );

      await tester.pumpAndSettle();
      expect(search.workItemCalls.map((c) => c.text), ['boar']);
      expect(search.codeCalls.map((c) => c.text), ['boar']);
      expect(search.pullRequestCalls.map((c) => c.text), ['boar']);
    });

    testWidgets('pull requests are matched from the cache while the API '
        'kinds are still in flight', (tester) async {
      search.pullRequestsCached = SearchResults<PullRequestSearchHit>(
        items: [prHit(8348, 'Board drag and drop')],
        total: 1,
      );
      search.gate('board');
      await pump(tester);
      await tester.enterText(field(), 'board');
      await tester.pump(SearchPage.debounce);
      await tester.pump();
      await tester.pump();

      expect(find.text('Board drag and drop'), findsOneWidget);
      expect(find.textContaining('Searching Work items'), findsOneWidget);

      search.gates['board']!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a late answer to an older query is dropped', (tester) async {
      search.workItems = (text) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(1, title: 'answer to $text')],
        total: 1,
      );
      search.gate('board');
      await pump(tester);
      await tester.enterText(field(), 'board');
      await tester.pump(SearchPage.debounce);
      await tester.pump();

      // The user types on; the first query's answer arrives afterwards.
      await tester.enterText(field(), 'boards');
      await tester.pump(SearchPage.debounce);
      search.gates['board']!.complete();
      await tester.pumpAndSettle();

      expect(find.text('answer to board'), findsNothing);
      expect(find.text('answer to boards'), findsOneWidget);
    });
  });

  group('cached first, live second', () {
    testWidgets('the cached copy is shown with its age, then replaced', (
      tester,
    ) async {
      search.workItemsCached = (
        value: SearchResults<WorkItemSearchHit>(
          items: [workItemHit(1, title: 'from the cache')],
          total: 1,
        ),
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(2, title: 'from the service')],
        total: 1,
      );
      search.gate('board');
      await pump(tester);
      await tester.enterText(field(), 'board');
      await tester.pump(SearchPage.debounce);
      await tester.pump();
      await tester.pump();

      expect(find.text('from the cache'), findsOneWidget);
      expect(find.text('cached · 3m'), findsOneWidget);

      search.gates['board']!.complete();
      await tester.pumpAndSettle();
      expect(find.text('from the service'), findsOneWidget);
      expect(find.text('from the cache'), findsNothing);
      expect(find.text('cached · 3m'), findsNothing);
    });

    testWidgets('offline keeps the cached copy and says so', (tester) async {
      search.workItemsCached = (
        value: SearchResults<WorkItemSearchHit>(
          items: [workItemHit(1, title: 'from the cache')],
          total: 1,
        ),
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      search.workItemsThrows = const AdoNetworkException('no route to host');
      await pump(tester, q: 'board');

      expect(find.text('from the cache'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
    });
  });

  group('decision D9: the grouped view', () {
    setUp(() {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [for (var i = 0; i < 7; i++) workItemHit(15500 + i)],
        total: 1234,
      );
      search.code = (_) => CodeSearchResults(
        count: 12,
        hits: [codeHit('board.dart')],
        infoCode: 0,
      );
      search.pullRequests = (_) => SearchResults<PullRequestSearchHit>(
        items: [prHit(8348, 'Board drag and drop')],
        total: 1,
      );
    });

    testWidgets('three sections, in order, with their totals', (tester) async {
      await pump(tester, q: 'board');

      expect(find.text('Work items · 1,234'), findsOneWidget);
      expect(find.text('Code · 12'), findsOneWidget);
      expect(find.text('Pull requests · 1'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Work items · 1,234')).dy,
        lessThan(tester.getTopLeft(find.text('Code · 12')).dy),
      );
      // Five rows per section, whatever came back.
      expect(find.byType(ListTile).evaluate().length, greaterThan(0));
      expect(find.text('#15505'), findsNothing);
    });

    testWidgets('See all opens that kind with the query and the scope', (
      tester,
    ) async {
      await pump(tester, q: 'board');
      await tester.tap(find.text('See all').first);
      await tester.pumpAndSettle();

      expect(find.text('1,234 results for "board"'), findsOneWidget);
      // The See-all list shows every row it was given, not five.
      expect(find.byType(PopupMenuButton<SearchOrder>), findsOneWidget);
    });

    testWidgets('an empty section is one quiet line and an error stays in '
        'its own section', (tester) async {
      search.workItems = (_) => const SearchResults<WorkItemSearchHit>();
      search.codeThrows = const CodeSearchUnavailable();
      await pump(tester, q: 'board');

      expect(find.text('No work items'), findsOneWidget);
      expect(find.textContaining('Code Search extension'), findsOneWidget);
      expect(find.text('Pull requests · 1'), findsOneWidget);
    });
  });

  group('the See-all views', () {
    testWidgets('decision D4: the chips re-run the query with the picked '
        'types and states', (tester) async {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(15500)],
        total: 1,
        facets: const SearchFacets(
          types: [
            SearchFacet(name: 'Bug', count: 12),
            SearchFacet(name: 'Task', count: 3),
          ],
          states: [SearchFacet(name: 'Active', count: 9)],
        ),
      );
      // Wide enough that every chip is on screen and tappable.
      await pump(
        tester,
        q: 'board',
        kind: SearchKind.workItems,
        size: const Size(1000, 1200),
      );
      expect(find.text('Bug (12)'), findsOneWidget);

      await tester.tap(find.text('Bug (12)'));
      await tester.pumpAndSettle();
      expect(search.workItemCalls.last.types, ['Bug']);

      await tester.tap(find.text('Active (9)'));
      await tester.pumpAndSettle();
      expect(search.workItemCalls.last.types, ['Bug']);
      expect(search.workItemCalls.last.states, ['Active']);

      // Tapping the same chip again lets it go.
      await tester.tap(find.text('Bug (12)'));
      await tester.pumpAndSettle();
      expect(search.workItemCalls.last.types, isEmpty);
    });

    testWidgets('the sort menu asks for the changed date order', (
      tester,
    ) async {
      search.workItems = (_) =>
          SearchResults<WorkItemSearchHit>(items: [workItemHit(1)], total: 1);
      await pump(tester, q: 'board', kind: SearchKind.workItems);
      await tester.tap(find.byType(PopupMenuButton<SearchOrder>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Changed date'));
      await tester.pumpAndSettle();

      expect(search.workItemCalls.last.order, SearchOrder.changedDate);
    });

    testWidgets('scrolling to the end asks for the next page', (tester) async {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [
          for (var i = 0; i < 50; i++) workItemHit(15500 + i, title: 'item $i'),
        ],
        total: 120,
      );
      await pump(tester, q: 'board', kind: SearchKind.workItems);
      expect(search.workItemCalls, hasLength(1));

      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(search.workItemCalls.last.skip, 50);
    });

    testWidgets('only the named kind is searched', (tester) async {
      await pump(tester, q: 'board', kind: SearchKind.code);
      expect(search.codeCalls, hasLength(1));
      expect(search.workItemCalls, isEmpty);
      expect(search.pullRequestCalls, isEmpty);
    });
  });

  group('decision D1: the scope switch', () {
    testWidgets('All searches every project and names it on the row', (
      tester,
    ) async {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(1, project: 'Another project')],
        total: 1,
      );
      await pump(tester, q: 'board', size: const Size(1000, 1200));
      expect(search.workItemCalls.last.project, 'Scratch');
      expect(find.text('Another project'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(search.workItemCalls.last.project, isNull);
      expect(find.text('Another project'), findsOneWidget);
    });

    testWidgets('a phone shows the switch as icons only', (tester) async {
      await pump(tester);
      expect(find.text('Project'), findsNothing);
      expect(find.byIcon(Icons.language), findsOneWidget);
    });
  });

  group('decision D5: recents', () {
    testWidgets('a sent query is remembered, and tapping one runs it', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(field(), 'board');
      await tester.pump(SearchPage.debounce);
      await tester.pumpAndSettle();
      expect(recents.entries, ['board']);

      await tester.enterText(field(), '');
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsOneWidget);

      await tester.tap(find.text('board'));
      await tester.pumpAndSettle();
      expect(search.workItemCalls.last.text, 'board');
    });

    testWidgets('a keystroke is not a query', (tester) async {
      await pump(tester);
      await tester.enterText(field(), 'boa');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field(), 'boar');
      await tester.pump(SearchPage.debounce);
      await tester.pumpAndSettle();
      expect(recents.entries, [
        'boar',
      ], reason: 'only the debounced send is remembered');
    });

    testWidgets('swiping removes one and Clear empties the list', (
      tester,
    ) async {
      recents.entries.addAll(['board', 'pipeline']);
      await pump(tester);
      expect(find.text('pipeline'), findsOneWidget);

      await tester.drag(find.text('pipeline'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(recents.entries, ['board']);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(recents.entries, isEmpty);
      expect(find.text('Recent'), findsNothing);
    });
  });

  group('taps', () {
    testWidgets('a work item hit opens its own project', (tester) async {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(15503, project: 'Another project')],
        total: 1,
      );
      await pump(tester, q: 'board', scope: SearchScope.org);
      await tester.tap(find.text('Board drag and drop'));
      await tester.pumpAndSettle();
      expect(find.text('item 15503'), findsOneWidget);
    });

    testWidgets('a pull request hit opens the pull request', (tester) async {
      search.pullRequests = (_) => SearchResults<PullRequestSearchHit>(
        items: [prHit(8348, 'A pull request')],
        total: 1,
      );
      await pump(tester, q: 'pull');
      await tester.tap(find.text('A pull request'));
      await tester.pumpAndSettle();
      expect(find.text('pr 8348'), findsOneWidget);
    });

    testWidgets('a code hit opens the file at its branch', (tester) async {
      search.code = (_) => CodeSearchResults(
        count: 1,
        hits: [codeHit('board.dart')],
        infoCode: 0,
      );
      await pump(tester, q: 'board');
      await tester.tap(find.text('board.dart'));
      await tester.pumpAndSettle();
      expect(find.text('file /lib/board.dart'), findsOneWidget);
    });
  });

  group('every width, both themes, the largest text', () {
    for (final size in const [Size(402, 874), Size(1032, 1376)]) {
      for (final brightness in Brightness.values) {
        testWidgets('${size.width.toInt()} dp, ${brightness.name}: the '
            'grouped view draws', (tester) async {
          search.workItems = (_) => SearchResults<WorkItemSearchHit>(
            items: [workItemHit(15503)],
            total: 1,
          );
          search.code = (_) => CodeSearchResults(
            count: 1,
            hits: [codeHit('board.dart')],
            infoCode: 0,
          );
          search.pullRequests = (_) => SearchResults<PullRequestSearchHit>(
            items: [prHit(8348, 'Board drag and drop')],
            total: 1,
          );
          await pump(tester, q: 'board', size: size, brightness: brightness);
          expect(tester.takeException(), isNull);
          expect(find.text('Work items · 1'), findsOneWidget);
        });
      }
    }

    testWidgets('xxxL text does not overflow the app bar or the rows', (
      tester,
    ) async {
      search.workItems = (_) => SearchResults<WorkItemSearchHit>(
        items: [workItemHit(15503)],
        total: 1234,
        facets: const SearchFacets(
          types: [SearchFacet(name: 'Bug', count: 1234)],
        ),
      );
      await pump(
        tester,
        q: 'board',
        kind: SearchKind.workItems,
        textScale: 3.1,
      );
      expect(tester.takeException(), isNull);
      // An app bar clips its title rather than throwing, so the overflow
      // check cannot see a squeezed field: assert the height the bar was
      // given instead.
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
        greaterThan(kToolbarHeight),
      );

      await pump(tester, q: 'board', textScale: 3.1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar grows with the text, then stops', (tester) async {
      // The app bar holds a text field; a fixed 56 dp toolbar clips it at
      // accessibility sizes, and an unbounded one would swallow the page.
      Future<double> heightAt(double scale) async {
        late double height;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: Builder(
                builder: (context) {
                  height = SearchPage.toolbarHeightFor(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        return height;
      }

      expect(await heightAt(1), kToolbarHeight);
      expect(await heightAt(1.2), greaterThan(kToolbarHeight));
      // Past the cap the AppBar stops scaling its title, so the bar stops
      // growing too.
      expect(
        await heightAt(3.1),
        closeTo((kToolbarHeight - 8) * SearchPage.titleScaleCap + 8, 0.001),
      );
      expect(await heightAt(3.1), await heightAt(2));
    });
  });
}
