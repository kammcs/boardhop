import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/db/json_cache.dart';
import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/data/repositories/wiki_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wiki_models_test.dart' show treeJson, wikiJson, wikiId, projectId;

const account = 'kelly@kammcs.com-home';
const org = 'puremedia';
const project = 'DevOps Mobile App';

/// An answer with the headers a wiki call carries.
class _Answer {
  _Answer(this.body, {this.status = 200, this.headers = const {}});
  final Object body;
  final int status;
  final Map<String, List<String>> headers;
}

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};

  /// Answers handed out in turn for a path part, for the paged calls.
  final Map<String, List<_Answer>> queued = <String, List<_Answer>>{};

  RequestOptions get last => requests.last;
  Iterable<RequestOptions> matching(String part) =>
      requests.where((r) => r.uri.toString().contains(part));
  RequestOptions? firstMatching(String part) => matching(part).firstOrNull;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.toString();
    for (final entry in queued.entries) {
      if (path.contains(entry.key) && entry.value.isNotEmpty) {
        final answer = entry.value.length == 1
            ? entry.value.first
            : entry.value.removeAt(0);
        return _body(answer);
      }
    }
    final keys = answers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final key = keys.firstWhere(path.contains, orElse: () => '');
    final answer = answers[key];
    return _body(
      answer is _Answer
          ? answer
          : _Answer(answer ?? const <String, dynamic>{'value': []}),
    );
  }

  ResponseBody _body(_Answer answer) => ResponseBody.fromString(
    jsonEncode(answer.body),
    answer.status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...answer.headers,
    },
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> listAnswer() => {
  'count': 1,
  'value': [wikiJson()],
};

Map<String, dynamic> pageAnswer({
  int id = 238,
  String path = '/Boardhop/Constructs',
}) => {
  'id': id,
  'path': path,
  'order': 1,
  'gitItemPath': '/Boardhop/Constructs.md',
  'content': '# Constructs\n',
  'subPages': <Object?>[],
  'remoteUrl':
      'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId'
      '?pagePath=%2FBoardhop%2FConstructs',
};

Map<String, dynamic> batchPage(List<MapEntry<String, int>> rows) => {
  'count': rows.length,
  'value': [
    for (final r in rows) {'path': r.key, 'id': r.value},
  ],
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late AdoClient client;
  late WikiRepository repository;

  setUp(() {
    adapter = _FakeAdapter();
    db = AppDatabase(NativeDatabase.memory());
    client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    );
    repository = WikiRepository(
      client,
      RepoRepository(client, db),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  group('wikis', () {
    test(
      'reads the project route at 7.1 and parses the project wiki',
      () async {
        adapter.answers['wiki/wikis'] = listAnswer();

        final wikis = await repository.wikis(org, project);

        final uri = adapter.last.uri;
        expect(uri.host, 'dev.azure.com');
        expect(uri.path, '/$org/DevOps%20Mobile%20App/_apis/wiki/wikis');
        // Every wiki route is released; no preview version anywhere.
        expect(uri.queryParameters['api-version'], '7.1');
        expect(wikis.single.id, wikiId);
        expect(wikis.single.isProjectWiki, isTrue);
        expect(wikis.single.version, 'wikiMaster');
      },
    );

    test('the project wiki sorts before code wikis', () async {
      adapter.answers['wiki/wikis'] = {
        'count': 3,
        'value': [
          {'id': 'c2', 'name': 'zebra.wiki', 'type': 'codeWiki'},
          {'id': 'c1', 'name': 'Alpha.wiki', 'type': 'codeWiki'},
          wikiJson(),
        ],
      };

      final wikis = await repository.wikis(org, project);

      expect(
        [for (final w in wikis) w.name],
        ['DevOps-Mobile-App.wiki', 'Alpha.wiki', 'zebra.wiki'],
      );
    });

    test('caches under wiki:list and serves the second call', () async {
      adapter.answers['wiki/wikis'] = listAnswer();

      await repository.wikis(org, project);
      await repository.wikis(org, project);

      expect(adapter.matching('_apis/wiki/wikis?').length, 1);
      expect(
        await JsonCache(
          db,
          namespace: account,
        ).get(WikiRepository.listKey(org, project)),
        isNotNull,
      );
      expect((await repository.cachedWikis(org, project))!.single.id, wikiId);
      expect(await repository.cachedWikis(org, 'Other'), isNull);
    });

    test('refresh goes back to the service', () async {
      adapter.answers['wiki/wikis'] = listAnswer();

      await repository.wikis(org, project);
      await repository.wikis(org, project, refresh: true);

      expect(adapter.matching('_apis/wiki/wikis?').length, 2);
    });

    test('an offline refresh falls back to the cached list', () async {
      adapter.answers['wiki/wikis'] = listAnswer();
      await repository.wikis(org, project);
      adapter.answers['wiki/wikis'] = _Answer({'message': 'boom'}, status: 500);

      final wikis = await repository.wikis(org, project, refresh: true);

      expect(wikis.single.id, wikiId);
    });
  });

  group('tree', () {
    void wireTree({List<List<MapEntry<String, int>>>? batches}) {
      adapter.queued['pages?path=%2F&recursionLevel=full'] = [
        _Answer(treeJson()),
      ];
      final pages =
          batches ??
          [
            [
              const MapEntry('/Boardhop', 236),
              const MapEntry('/Boardhop/Constructs', 238),
              const MapEntry('/Boardhop/Links', 240),
              const MapEntry('/Boardhop/Links/Deep child', 242),
              const MapEntry('/Boardhop/Links/Re-Order', 244),
              const MapEntry('/Boardhop/Links/Deep child/Level 4', 246),
              const MapEntry('/Boardhop/Pushed page', 248),
              const MapEntry('/Boardhop/Pushed tidy', 249),
            ],
          ];
      adapter.queued['pagesbatch'] = [
        for (var i = 0; i < pages.length; i++)
          _Answer(
            batchPage(pages[i]),
            headers: i == pages.length - 1
                ? const {}
                : {
                    'x-ms-continuationtoken': ['${pages[i].last.value}'],
                  },
          ),
      ];
    }

    test('asks for the whole tree without content, then the ids', () async {
      wireTree();

      final root = await repository.tree(org, project, wikiId);

      final treeCall = adapter.firstMatching('recursionLevel=full')!;
      expect(
        treeCall.uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/wiki/wikis/$wikiId/pages',
      );
      expect(treeCall.uri.queryParameters['path'], '/');
      expect(treeCall.uri.queryParameters['includeContent'], 'false');
      expect(treeCall.uri.queryParameters['api-version'], '7.1');

      final batch = adapter.firstMatching('pagesbatch')!;
      expect(batch.method, 'POST');
      expect((batch.data as Map)['top'], WikiRepository.batchSize);

      expect(root.find('/Boardhop/Constructs')!.id, 238);
      expect(root.find('/Boardhop/Links/Deep child/Level 4')!.id, 246);
      expect(root.flatten().where((n) => !n.isRoot && n.id == null), isEmpty);
    });

    test('pages the batch through the continuation header', () async {
      wireTree(
        batches: [
          [
            const MapEntry('/Boardhop', 236),
            const MapEntry('/Boardhop/Constructs', 238),
          ],
          [
            const MapEntry('/Boardhop/Links', 240),
            const MapEntry('/Boardhop/Links/Deep child', 242),
            const MapEntry('/Boardhop/Links/Re-Order', 244),
            const MapEntry('/Boardhop/Links/Deep child/Level 4', 246),
            const MapEntry('/Boardhop/Pushed page', 248),
            const MapEntry('/Boardhop/Pushed tidy', 249),
          ],
        ],
      );

      final root = await repository.tree(org, project, wikiId);

      final calls = adapter.matching('pagesbatch').toList();
      expect(calls.length, 2);
      expect((calls.first.data as Map)['continuationToken'], isNull);
      // The token of the first page is the last id it answered.
      expect((calls.last.data as Map)['continuationToken'], '238');
      expect(root.find('/Boardhop/Pushed tidy')!.id, 249);
    });

    test('a repeating continuation token stops the loop', () async {
      adapter.queued['pages?path=%2F&recursionLevel=full'] = [
        _Answer(treeJson()),
      ];
      adapter.queued['pagesbatch'] = [
        _Answer(
          batchPage([const MapEntry('/Boardhop', 236)]),
          headers: const {
            'x-ms-continuationtoken': ['stuck'],
          },
        ),
        _Answer(
          batchPage([const MapEntry('/Boardhop/Constructs', 238)]),
          headers: const {
            'x-ms-continuationtoken': ['stuck'],
          },
        ),
      ];

      final root = await repository.tree(org, project, wikiId);

      expect(adapter.matching('pagesbatch').length, 2);
      expect(root.find('/Boardhop/Constructs')!.id, 238);
    });

    test('a code wiki\'s branch travels on both calls', () async {
      wireTree();

      await repository.tree(org, project, wikiId, version: 'main');

      final treeCall = adapter.firstMatching('recursionLevel=full')!;
      expect(treeCall.uri.queryParameters['versionDescriptor.version'], 'main');
      // The wiki routes take the version alone; only the git routes an
      // attachment goes through spell the type out (spike w37).
      expect(
        treeCall.uri.queryParameters['versionDescriptor.versionType'],
        isNull,
      );
      expect(
        adapter
            .firstMatching('pagesbatch')!
            .uri
            .queryParameters['versionDescriptor.version'],
        'main',
      );
    });

    test('caches the joined tree and serves it back with the ids', () async {
      wireTree();

      await repository.tree(org, project, wikiId);
      final again = await repository.tree(org, project, wikiId);

      expect(adapter.matching('recursionLevel=full').length, 1);
      expect(again.find('/Boardhop/Links')!.id, 240);
      final cached = await repository.cachedTree(org, project, wikiId);
      expect(cached!.find('/Boardhop/Links')!.id, 240);
      // The branch is part of the key.
      expect(
        await repository.cachedTree(org, project, wikiId, version: 'main'),
        isNull,
      );
    });
  });

  group('page', () {
    test('reads by path with content and keeps the ETag header', () async {
      adapter.answers['/pages'] = _Answer(
        pageAnswer(),
        headers: const {
          'etag': ['"e33a90d23344d6dacb346e7a12def64a48e0a05f"'],
        },
      );

      final page = await repository.page(
        org,
        project,
        wikiId,
        path: '/Boardhop/Constructs',
      );

      final uri = adapter.last.uri;
      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/wiki/wikis/$wikiId/pages',
      );
      expect(uri.queryParameters['path'], '/Boardhop/Constructs');
      expect(uri.queryParameters['includeContent'], 'true');
      expect(page.id, 238);
      expect(page.content, '# Constructs\n');
      expect(page.etag, 'e33a90d23344d6dacb346e7a12def64a48e0a05f');
    });

    test('reads by id on the pages/{id} route', () async {
      adapter.answers['/pages/238'] = _Answer(
        pageAnswer(),
        headers: const {
          'etag': ['"e33a90d2"'],
        },
      );

      final page = await repository.page(org, project, wikiId, id: 238);

      expect(
        adapter.last.uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/wiki/wikis/$wikiId/pages/238',
      );
      expect(adapter.last.uri.queryParameters['path'], isNull);
      expect(page.path, '/Boardhop/Constructs');
      expect(page.etag, 'e33a90d2');
    });

    test('a page read by id is found by path afterwards, and back', () async {
      adapter.answers['/pages/238'] = _Answer(pageAnswer());

      await repository.page(org, project, wikiId, id: 238);

      final byPath = await repository.cachedPage(
        org,
        project,
        wikiId,
        path: '/Boardhop/Constructs',
      );
      expect(byPath!.page.id, 238);
      final byId = await repository.cachedPage(org, project, wikiId, id: 238);
      expect(byId!.page.path, '/Boardhop/Constructs');
    });

    test('is cache-first: the second read makes no call', () async {
      adapter.answers['/pages'] = _Answer(pageAnswer());

      await repository.page(org, project, wikiId, path: '/Boardhop/Constructs');
      await repository.page(org, project, wikiId, path: '/Boardhop/Constructs');

      expect(adapter.matching('/pages').length, 1);
      final cached = await repository.cachedPage(
        org,
        project,
        wikiId,
        path: '/Boardhop/Constructs',
      );
      expect(cached!.page.content, '# Constructs\n');
      expect(
        DateTime.now().difference(cached.fetchedAt),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test(
      'refresh goes back, and an offline refresh keeps the cached copy',
      () async {
        adapter.answers['/pages'] = _Answer(pageAnswer());
        await repository.page(
          org,
          project,
          wikiId,
          path: '/Boardhop/Constructs',
        );
        adapter.answers['/pages'] = _Answer({'message': 'down'}, status: 500);

        final page = await repository.page(
          org,
          project,
          wikiId,
          path: '/Boardhop/Constructs',
          refresh: true,
        );

        expect(page.content, '# Constructs\n');
      },
    );

    test('a missing page raises the service\'s 404', () async {
      adapter.answers['/pages'] = _Answer({
        'message': 'Wiki page could not be found.',
        'typeKey': 'WikiPageNotFoundException',
      }, status: 404);

      expect(
        () => repository.page(org, project, wikiId, path: '/nope'),
        throwsA(isA<AdoNotFoundException>()),
      );
    });
  });

  group('the TF400813 refusal', () {
    test('surfaces as WikiUnavailable, not as a sign-in', () async {
      adapter.answers['wiki/wikis'] = _Answer({
        'message':
            'TF400813: The user is not authorized to access this '
            'resource.',
        'typeKey': 'InvalidIdentityException',
      }, status: 401);

      await expectLater(
        repository.wikis(org, project),
        throwsA(
          isA<WikiUnavailable>()
              .having((e) => e.message, 'message', contains('wiki'))
              // Not an AdoAuthException: raising sign-in here would loop.
              .having((e) => e is AdoAuthException, 'is auth', isFalse),
        ),
      );
    });

    test('the tree and a page refuse the same way', () async {
      final refusal = _Answer({
        'message': 'TF400813: not authorized',
      }, status: 401);
      adapter.answers['pages'] = refusal;

      await expectLater(
        repository.tree(org, project, wikiId),
        throwsA(isA<WikiUnavailable>()),
      );
      await expectLater(
        repository.page(org, project, wikiId, path: '/Boardhop'),
        throwsA(isA<WikiUnavailable>()),
      );
    });

    test('an ordinary 401 still asks for sign-in', () async {
      adapter.answers['wiki/wikis'] = _Answer({
        'message': 'The token is expired',
      }, status: 401);

      await expectLater(
        repository.wikis(org, project),
        throwsA(
          isA<AdoAuthException>().having(
            (e) => e is WikiUnavailable,
            'is refusal',
            isFalse,
          ),
        ),
      );
    });
  });

  group('attachments', () {
    final wiki = Wiki.fromJson(wikiJson());

    test('the URL is the Items API on the wiki repository, at the branch', () {
      final uri = repository.attachmentUri(
        org,
        project,
        wiki,
        '/.attachments/boardhop-w37-b64.png',
      );

      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/git/repositories/$wikiId/items',
      );
      expect(uri.queryParameters['path'], '/.attachments/boardhop-w37-b64.png');
      expect(uri.queryParameters['versionDescriptor.version'], 'wikiMaster');
      expect(uri.queryParameters['versionDescriptor.versionType'], 'branch');
      expect(uri.queryParameters[r'$format'], 'octetStream');
      expect(uri.queryParameters['api-version'], '7.1');
    });

    test('the bytes go through RepoRepository.fileBytes, same URL', () async {
      adapter.answers['/items'] = const <String, dynamic>{};

      await repository.attachmentBytes(
        org,
        project,
        wiki,
        '/.attachments/boardhop-w37-b64.png',
      );

      final called = adapter.last.uri;
      expect(called.path, contains('/git/repositories/$wikiId/items'));
      expect(
        called.queryParameters['path'],
        '/.attachments/boardhop-w37-b64.png',
      );
      expect(called.queryParameters['versionDescriptor.version'], 'wikiMaster');
    });

    test('a code wiki prefixes its mappedPath (K8, unverified)', () {
      final code = Wiki.fromJson(const {
        'id': 'c1',
        'name': 'docs.wiki',
        'type': 'codeWiki',
        'repositoryId': 'repo-1',
        'mappedPath': '/docs',
        'versions': [
          {'version': 'main'},
        ],
      });

      expect(
        WikiRepository.repositoryPath(code, '/.attachments/x.png'),
        '/docs/.attachments/x.png',
      );
      // Already inside the folder: not prefixed twice.
      expect(
        WikiRepository.repositoryPath(code, '/docs/.attachments/x.png'),
        '/docs/.attachments/x.png',
      );
      // A project wiki is published from the root, so nothing changes.
      expect(
        WikiRepository.repositoryPath(wiki, '/.attachments/x.png'),
        '/.attachments/x.png',
      );
      expect(
        repository
            .attachmentUri(org, project, code, '.attachments/x.png')
            .queryParameters['path'],
        '/docs/.attachments/x.png',
      );
    });
  });

  group('lastChange', () {
    final wiki = Wiki.fromJson(wikiJson());

    test('reads the newest commit on the page\'s markdown file', () async {
      adapter.answers['/commits'] = {
        'count': 1,
        'value': [
          {
            'commitId': 'abc',
            'author': {'name': 'Kelly Kamm', 'date': '2026-09-15T16:40:00Z'},
            'comment': 'spike w37',
          },
        ],
      };

      final change = await repository.lastChange(
        org,
        project,
        wiki,
        '/Boardhop/Constructs.md',
      );

      final uri = adapter.last.uri;
      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/git/repositories/$wikiId/commits',
      );
      expect(
        uri.queryParameters['searchCriteria.itemPath'],
        '/Boardhop/Constructs.md',
      );
      expect(uri.queryParameters[r'searchCriteria.$top'], '1');
      expect(
        uri.queryParameters['searchCriteria.itemVersion.version'],
        'wikiMaster',
      );
      expect(change!.author, 'Kelly Kamm');
      expect(change.comment, 'spike w37');
    });

    test('is cached, and a file with no history is null', () async {
      adapter.answers['/commits'] = {
        'count': 1,
        'value': [
          {
            'commitId': 'abc',
            'author': {'name': 'Kelly Kamm', 'date': '2026-09-15T16:40:00Z'},
            'comment': 'spike w37',
          },
        ],
      };
      await repository.lastChange(org, project, wiki, '/Boardhop.md');
      await repository.lastChange(org, project, wiki, '/Boardhop.md');
      expect(adapter.matching('/commits').length, 1);

      adapter.answers['/commits'] = {'count': 0, 'value': <Object?>[]};
      expect(
        await repository.lastChange(org, project, wiki, '/Other.md'),
        isNull,
      );
      // Nothing to ask about is answered without a call.
      final before = adapter.requests.length;
      expect(await repository.lastChange(org, project, wiki, '  '), isNull);
      expect(adapter.requests.length, before);
    });
  });
}
