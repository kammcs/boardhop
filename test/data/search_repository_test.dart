import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/search.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/search_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_models_test.dart' show searchResponse;

const account = 'kelly@kammcs.com-home';
const org = 'contoso';
const project = 'Scratch';

/// Canned-response adapter: the repository is exercised through the real
/// `AdoClient`, so the URL and the body it builds are what the tests read.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  int status = 200;
  bool offline = false;

  RequestOptions get last => requests.last;
  Map<String, dynamic> get lastBody =>
      (last.data as Map).cast<String, dynamic>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    final key = answers.keys.firstWhere(
      (k) => options.uri.path.contains(k),
      orElse: () => '',
    );
    final body = answers[key] ?? const <String, dynamic>{};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The scratch wiki's answer to "Boardhop" (spike w37 §8).
Map<String, dynamic> wikiResponse() => {
  'count': 1,
  'infoCode': 0,
  'results': [
    {
      'fileName': 'Boardhop.md',
      'path': '/Boardhop.md',
      'collection': {'name': 'puremedia'},
      'project': {
        'id': '98720989-0195-48cb-ae2e-0e58ec1bb9a9',
        'name': 'DevOps Mobile App',
      },
      'wiki': {
        'name': 'DevOps-Mobile-App.wiki',
        'id': '2bd59283-17a5-4fd0-b964-cd9a4189f721',
        'mappedPath': '/',
        'version': 'wikiMaster',
      },
      'contentId': 'cfb72c3bac53fad93c24ef5408a5276183a911bf',
      'hits': [
        {
          'fieldReferenceName': 'content',
          'highlights': ['<highlighthit>Boardhop</highlighthit> wiki spike'],
        },
      ],
    },
  ],
  'facets': {
    'Project': [
      {'name': 'DevOps Mobile App', 'resultCount': 1},
    ],
  },
};

Map<String, dynamic> codeResponse() => {
  'count': 1,
  'infoCode': 0,
  'results': [
    {
      'fileName': 'search_repository.dart',
      'path': '/lib/data/repositories/search_repository.dart',
      'repository': {'id': 'r-1', 'name': 'boardhop'},
      'project': {'id': 'p-scratch', 'name': 'Scratch'},
      'versions': [
        {'branchName': 'main'},
      ],
      'matches': {
        'content': [
          {'charOffset': 10, 'length': 3},
        ],
      },
    },
  ],
};

Map<String, dynamic> prList() => {
  'value': [
    _pr(1, 'Board drag and drop', 'feature/board', 'Bay Wilkins'),
    _pr(2, 'Pipelines: retry a stage', 'feature/retry', 'Ada Lovelace'),
    _pr(3, 'Tidy the theme', 'ada/tokens', 'Ada Lovelace'),
    _pr(4, 'Ada writes the readme', 'chore/readme', 'Bay Wilkins'),
    _pr(
      5,
      'Other project work',
      'feature/other',
      'Ada Lovelace',
      projectName: 'Atlas',
    ),
  ],
};

Map<String, dynamic> _pr(
  int id,
  String title,
  String branch,
  String author, {
  String projectName = project,
}) => {
  'pullRequestId': id,
  'title': title,
  'status': 'active',
  'repository': {
    'id': 'r-$id',
    'name': 'boardhop',
    'project': {'id': 'p-$projectName', 'name': projectName},
  },
  'sourceRefName': 'refs/heads/$branch',
  'targetRefName': 'refs/heads/main',
  'createdBy': {'displayName': author, 'uniqueName': 'x@example.test'},
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late SearchRepository repository;

  setUp(() {
    adapter = _FakeAdapter()
      ..answers['workitemsearchresults'] = searchResponse()
      ..answers['codesearchresults'] = codeResponse()
      ..answers['wikisearchresults'] = wikiResponse()
      ..answers['pullrequests'] = prList();
    db = AppDatabase(NativeDatabase.memory());
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    );
    repository = SearchRepository(
      client,
      PullRequestRepository(client, db, account),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  group('work item search', () {
    test('posts to the org, with the project as a body filter', () async {
      final results = await repository.searchWorkItems(
        org,
        project: project,
        text: 'boardhop',
      );

      expect(
        adapter.last.uri.toString(),
        'https://almsearch.dev.azure.com/contoso/_apis/search/'
        'workitemsearchresults?api-version=7.1',
      );
      expect(adapter.last.method, 'POST');
      expect(adapter.lastBody['searchText'], 'boardhop');
      expect(adapter.lastBody[r'$top'], 50);
      expect(adapter.lastBody[r'$skip'], 0);
      expect(adapter.lastBody['includeFacets'], isTrue);
      expect(adapter.lastBody['filters'], {
        'System.TeamProject': ['Scratch'],
      });
      expect(adapter.lastBody.containsKey(r'$orderBy'), isFalse);
      expect(results.items.single.id, 15503);
      expect(results.total, 42);
    });

    test(
      'All projects sends the same call without the project filter',
      () async {
        await repository.searchWorkItems(org, text: 'boardhop');
        expect(
          adapter.last.uri.path,
          '/contoso/_apis/search/workitemsearchresults',
        );
        expect(adapter.lastBody['filters'], isEmpty);
      },
    );

    test('chips and paging travel in the body', () async {
      await repository.searchWorkItems(
        org,
        project: project,
        text: 'boardhop',
        types: ['Task', 'Bug'],
        states: ['Active'],
        skip: 50,
        order: SearchOrder.changedDate,
      );
      expect(adapter.lastBody['filters'], {
        'System.TeamProject': ['Scratch'],
        'System.WorkItemType': ['Task', 'Bug'],
        'System.State': ['Active'],
      });
      expect(adapter.lastBody[r'$skip'], 50);
      expect(adapter.lastBody[r'$orderBy'], [
        {'field': 'system.changeddate', 'sortOrder': 'DESC'},
      ]);
    });

    test('shorter than the minimum sends nothing', () async {
      final results = await repository.searchWorkItems(
        org,
        project: project,
        text: 'bo',
      );
      expect(adapter.requests, isEmpty);
      expect(results.isEmpty, isTrue);
      expect(results.total, 0);
      expect(SearchRepository.minLength, 3);
      expect(SearchRepository.isSearchable('  bo  '), isFalse);
      expect(SearchRepository.isSearchable(' boa '), isTrue);
    });

    test('the answer is cached and read back without a call', () async {
      final fresh = await repository.searchWorkItems(
        org,
        project: project,
        text: 'boardhop',
      );
      final cached = await repository.cachedWorkItems(
        org,
        project: project,
        text: 'boardhop',
      );
      expect(adapter.requests, hasLength(1));
      expect(cached!.value, fresh);
      expect(cached.value.items.single.highlight!.plain, contains('boardhop'));
      expect(cached.fetchedAt.isAfter(DateTime(2020)), isTrue);
    });

    test(
      'another query, another page or another scope is another entry',
      () async {
        await repository.searchWorkItems(
          org,
          project: project,
          text: 'boardhop',
        );
        expect(
          await repository.cachedWorkItems(
            org,
            project: project,
            text: 'other',
          ),
          isNull,
        );
        expect(
          await repository.cachedWorkItems(org, text: 'boardhop'),
          isNull,
          reason: 'All projects is a different answer',
        );
        expect(
          await repository.cachedWorkItems(
            org,
            project: project,
            text: 'boardhop',
            skip: 50,
          ),
          isNull,
        );
      },
    );

    test('the same chips in another order hit the same entry', () async {
      await repository.searchWorkItems(
        org,
        project: project,
        text: 'boardhop',
        types: ['Bug', 'Task'],
      );
      expect(
        await repository.cachedWorkItems(
          org,
          project: project,
          text: 'boardhop',
          types: ['Task', 'Bug'],
        ),
        isNotNull,
      );
    });
  });

  group('cache eviction', () {
    test('keeps the last 30 searches and drops the oldest', () async {
      for (var i = 0; i < SearchRepository.maxCacheEntries + 2; i++) {
        await repository.searchWorkItems(org, project: project, text: 'qry$i');
      }
      final keys = await repository.cachedKeys();
      expect(keys, hasLength(SearchRepository.maxCacheEntries));
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'qry0'),
        isNull,
      );
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'qry1'),
        isNull,
      );
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'qry2'),
        isNotNull,
      );
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'qry31'),
        isNotNull,
      );
    });

    test('re-running a query moves it to the front of the queue', () async {
      await repository.searchWorkItems(org, project: project, text: 'keep');
      for (var i = 0; i < SearchRepository.maxCacheEntries; i++) {
        await repository.searchWorkItems(org, project: project, text: 'fill$i');
        if (i == 0) {
          // Touch it again: it must not be the one evicted.
          await repository.searchWorkItems(org, project: project, text: 'keep');
        }
      }
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'keep'),
        isNotNull,
      );
      expect(
        await repository.cachedWorkItems(org, project: project, text: 'fill0'),
        isNull,
      );
    });
  });

  group('code search', () {
    test('project scope filters by Project, org scope by nothing', () async {
      await repository.searchCode(org, project: project, text: 'todo');
      expect(
        adapter.last.uri.path,
        '/contoso/_apis/search/codesearchresults',
        reason: 'the project travels in the body, not the path',
      );
      expect(adapter.lastBody['filters'], {
        'Project': ['Scratch'],
      });

      await repository.searchCode(org, text: 'todo');
      expect(adapter.lastBody['filters'], isEmpty);
    });

    test('a repository filter goes with its project', () async {
      final page = await repository.searchCode(
        org,
        project: project,
        text: 'todo',
        repositoryName: 'boardhop',
      );
      expect(adapter.lastBody['filters'], {
        'Project': ['Scratch'],
        'Repository': ['boardhop'],
      });
      expect(page.hits.single.branch, 'main');
      expect(page.count, 1);
    });

    test('404 means the extension is missing, not "not found"', () async {
      adapter.status = 404;
      await expectLater(
        repository.searchCode(org, project: project, text: 'todo'),
        throwsA(
          isA<CodeSearchUnavailable>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('Code Search')),
        ),
      );
    });

    test('is cached like the other kinds', () async {
      await repository.searchCode(org, project: project, text: 'todo');
      final cached = await repository.cachedCode(
        org,
        project: project,
        text: 'todo',
      );
      expect(cached!.value.hits.single.fileName, 'search_repository.dart');
      expect(
        await repository.cachedCode(org, text: 'todo'),
        isNull,
        reason: 'org scope is its own entry',
      );
    });

    test('shorter than the minimum sends nothing', () async {
      final page = await repository.searchCode(org, text: 'to');
      expect(adapter.requests, isEmpty);
      expect(page.count, 0);
      expect(page.problem, isNull);
    });
  });

  group('wiki search (research/20 K4)', () {
    test('posts to the org, with the project as a body filter', () async {
      final results = await repository.searchWiki(
        org,
        project: project,
        text: 'boardhop',
      );

      expect(adapter.last.uri.host, 'almsearch.dev.azure.com');
      expect(
        adapter.last.uri.path,
        '/contoso/_apis/search/wikisearchresults',
        reason: 'the project travels in the body, like every other kind',
      );
      expect(adapter.last.uri.queryParameters['api-version'], '7.1');
      expect(adapter.lastBody['searchText'], 'boardhop');
      expect(adapter.lastBody[r'$skip'], 0);
      expect(adapter.lastBody[r'$top'], SearchRepository.pageSize);
      expect(adapter.lastBody['includeFacets'], isTrue);
      expect(adapter.lastBody['filters'], {
        'Project': ['Scratch'],
      });

      expect(results.total, 1);
      final hit = results.items.single;
      expect(hit.fileName, 'Boardhop.md');
      expect(hit.wikiName, 'DevOps-Mobile-App.wiki');
      // The service answers the git file path; the reader opens the page.
      expect(hit.pagePath, '/Boardhop');
      expect(hit.highlight!.plain, contains('wiki spike'));
      expect(results.facets.projects.single.name, 'DevOps Mobile App');
    });

    test('the All scope sends no project filter', () async {
      await repository.searchWiki(org, text: 'boardhop');

      expect(adapter.lastBody['filters'], isEmpty);
    });

    test('paging passes skip and top', () async {
      await repository.searchWiki(org, text: 'boardhop', skip: 50, top: 25);

      expect(adapter.lastBody[r'$skip'], 50);
      expect(adapter.lastBody[r'$top'], 25);
    });

    test('is cached under its own kind, per scope and page', () async {
      await repository.searchWiki(org, project: project, text: 'boardhop');

      final cached = await repository.cachedWiki(
        org,
        project: project,
        text: 'boardhop',
      );
      expect(cached!.value.items.single.pagePath, '/Boardhop');
      expect(
        await repository.cachedWiki(org, text: 'boardhop'),
        isNull,
        reason: 'org scope is its own entry',
      );
      expect(
        await repository.cachedWiki(
          org,
          project: project,
          text: 'boardhop',
          skip: 50,
        ),
        isNull,
      );
      expect(
        await repository.cachedKeys(),
        contains('search:wiki:contoso:Scratch:relevance:0:||:boardhop'),
      );
    });

    test('404 means the search extension is missing', () async {
      adapter.status = 404;

      await expectLater(
        repository.searchWiki(org, project: project, text: 'boardhop'),
        throwsA(isA<CodeSearchUnavailable>()),
      );
    });

    test('shorter than the minimum sends nothing', () async {
      final results = await repository.searchWiki(org, text: 'bo');

      expect(adapter.requests, isEmpty);
      expect(results.total, 0);
      expect(results.items, isEmpty);
    });
  });

  group('pull request matching', () {
    test('title matches come before branch, then author', () async {
      final results = await repository.searchPullRequests(org, text: 'ada');
      expect([for (final h in results.items) h.pullRequest.id], [4, 3, 2, 5]);
      expect(results.items.first.match, PrMatchField.title);
      expect(results.items[1].match, PrMatchField.branch);
      expect(results.items[2].match, PrMatchField.author);
      expect(results.total, 4);
    });

    test('asks the org for every active pull request', () async {
      await repository.searchPullRequests(org, text: 'ada');
      expect(adapter.last.uri.path, '/contoso/_apis/git/pullrequests');
      expect(
        adapter.last.uri.queryParameters['searchCriteria.status'],
        'active',
      );
      expect(
        adapter.last.uri.queryParameters.containsKey(
          'searchCriteria.reviewerId',
        ),
        isFalse,
        reason: 'PrListFilter.all asks for nobody in particular',
      );
    });

    test('a project scope keeps only that project', () async {
      final results = await repository.searchPullRequests(
        org,
        project: project,
        text: 'ada',
      );
      expect([for (final h in results.items) h.pullRequest.id], [4, 3, 2]);
    });

    test('the match ignores case and reaches the target branch', () async {
      final results = await repository.searchPullRequests(org, text: 'MAIN');
      expect(results.items, hasLength(5));
      expect(
        results.items.every((h) => h.match == PrMatchField.branch),
        isTrue,
      );
    });

    test('shorter than the minimum asks for nothing', () async {
      final results = await repository.searchPullRequests(org, text: 'ad');
      expect(adapter.requests, isEmpty);
      expect(results.isEmpty, isTrue);
    });

    test(
      'offline falls back to the inbox list the app already cached',
      () async {
        await repository.searchPullRequests(org, text: 'ada');
        adapter.offline = true;
        final results = await repository.searchPullRequests(org, text: 'ada');
        expect([for (final h in results.items) h.pullRequest.id], [4, 3, 2, 5]);
      },
    );

    test('offline with nothing cached still raises', () async {
      adapter.offline = true;
      await expectLater(
        repository.searchPullRequests(org, text: 'ada'),
        throwsA(isA<AdoNetworkException>()),
      );
    });

    test('the cached matcher runs without a call', () async {
      expect(await repository.cachedPullRequests(org, text: 'ada'), isNull);
      await repository.searchPullRequests(org, text: 'ada');
      final before = adapter.requests.length;
      final cached = await repository.cachedPullRequests(org, text: 'ada');
      expect(adapter.requests, hasLength(before));
      expect([for (final h in cached!.items) h.pullRequest.id], [4, 3, 2, 5]);
    });
  });

  group('failures', () {
    test('an auth failure travels untouched, for the page to raise', () async {
      adapter.status = 401;
      await expectLater(
        repository.searchWorkItems(org, project: project, text: 'boardhop'),
        throwsA(isA<AdoAuthException>()),
      );
    });

    test('other failures stay AdoExceptions for an inline message', () async {
      adapter.status = 500;
      await expectLater(
        repository.searchWorkItems(org, project: project, text: 'boardhop'),
        throwsA(isA<AdoServerException>()),
      );
    });
  });

  group('cache keys', () {
    test('spell out every part of the query', () {
      expect(
        SearchRepository.cacheKey(
          kind: SearchRepository.workItemKind,
          org: org,
          project: project,
          text: '  BoardHop ',
          types: ['Task', 'Bug'],
          states: ['Active'],
          order: SearchOrder.changedDate,
          skip: 50,
        ),
        'search:wi:contoso:Scratch:changedDate:50:Bug,Task|Active|:boardhop',
      );
      expect(
        SearchRepository.cacheKey(
          kind: SearchRepository.codeKind,
          org: org,
          text: 'todo',
        ),
        'search:code:contoso:*:relevance:0:||:todo',
      );
      expect(
        SearchRepository.cacheKey(
          kind: SearchRepository.wikiKind,
          org: org,
          project: project,
          text: 'Boardhop',
        ),
        'search:wiki:contoso:Scratch:relevance:0:||:boardhop',
      );
    });
  });
}
