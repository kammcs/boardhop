import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'puremedia';
const project = 'DevOps Mobile App';

/// The shared query spike w36 created in the scratch project.
const queryId = '8c808ce9-51d6-4cdf-a17a-17a70930d2f0';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  final Map<String, List<String>> extraHeaders = <String, List<String>>{};
  int status = 200;

  RequestOptions get last => requests.last;
  RequestOptions? firstMatching(String part) =>
      requests.where((r) => r.uri.toString().contains(part)).firstOrNull;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.toString();
    final keys = answers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final key = keys.firstWhere(path.contains, orElse: () => '');
    return ResponseBody.fromString(
      jsonEncode(answers[key] ?? const <String, dynamic>{'value': []}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...extraHeaders,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> queryAnswer() => {
  'id': queryId,
  'name': 'Boardhop dashboard spike',
  'path': 'Shared Queries/Boardhop dashboard spike',
  'queryType': 'flat',
  'isPublic': true,
  'columns': [
    {'referenceName': 'System.Id', 'name': 'ID'},
    {'referenceName': 'System.Title', 'name': 'Title'},
    {'referenceName': 'System.State', 'name': 'State'},
  ],
  'wiql': 'SELECT [System.Id] FROM WorkItems',
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late AdoClient client;
  late WorkItemRepository repository;

  setUp(() {
    adapter = _FakeAdapter();
    db = AppDatabase(NativeDatabase.memory());
    client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    );
    repository = WorkItemRepository(client, db, userId: account);
  });

  tearDown(() => db.close());

  group('queryMeta (research/19 §1)', () {
    test(r'reads queries/{id} with $expand=wiql', () async {
      adapter.answers['wit/queries/$queryId'] = queryAnswer();

      final meta = await repository.queryMeta(org, project, queryId);

      final uri = adapter.last.uri;
      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/wit/queries/$queryId',
      );
      // $expand=none carries neither the type nor the columns.
      expect(uri.queryParameters[r'$expand'], 'wiql');
      expect(uri.queryParameters['api-version'], '7.1');
      expect(meta.queryType, 'flat');
      expect(meta.isFlat, isTrue);
      expect(meta.columns, ['System.Id', 'System.Title', 'System.State']);
      expect(meta.wiql, startsWith('SELECT'));
    });

    test(
      'a tree query is not flat, which changes what the card draws',
      () async {
        adapter.answers['wit/queries/$queryId'] = {
          ...queryAnswer(),
          'queryType': 'tree',
        };
        final meta = await repository.queryMeta(org, project, queryId);
        expect(meta.isFlat, isFalse);
      },
    );

    test('is cached and the second call makes no request', () async {
      adapter.answers['wit/queries/$queryId'] = queryAnswer();

      await repository.queryMeta(org, project, queryId);
      await repository.queryMeta(org, project, queryId);

      expect(adapter.requests.length, 1);
      expect(WorkItemRepository.queryMetaKey(queryId), 'query:meta:$queryId');
    });

    test('a failure falls back to the cached definition', () async {
      adapter.answers['wit/queries/$queryId'] = queryAnswer();
      await repository.queryMeta(org, project, queryId);

      adapter.status = 500;
      final meta = await repository.queryMeta(
        org,
        project,
        queryId,
        refresh: true,
      );
      expect(meta.queryType, 'flat');
    });

    test('a failure with nothing cached throws', () async {
      adapter.status = 404;
      await expectLater(
        repository.queryMeta(org, project, queryId),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('queryCount', () {
    test('HEAD wiql/{id} answers X-Total-Count without the ids', () async {
      adapter.extraHeaders['X-Total-Count'] = ['416'];

      final count = await repository.queryCount(org, project, queryId);

      expect(count, 416);
      expect(adapter.requests.length, 1);
      expect(adapter.last.method, 'HEAD');
      expect(
        adapter.last.uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/wit/wiql/$queryId',
      );
      // No $top on the HEAD: the point is not to fetch anything.
      expect(adapter.last.uri.queryParameters.containsKey(r'$top'), isFalse);
    });

    test('falls back to the GET when the header is missing', () async {
      adapter.answers['wit/wiql/$queryId'] = {
        'workItems': [
          {'id': 15503},
          {'id': 15504},
        ],
      };

      final count = await repository.queryCount(org, project, queryId);

      expect(count, 2);
      expect(adapter.requests.map((r) => r.method), ['HEAD', 'GET']);
      expect(adapter.last.uri.queryParameters[r'$top'], '200');
    });

    test('falls back to the GET when HEAD is refused', () async {
      adapter.status = 405;
      // The GET answers, because the fake flips the status back.
      var head = true;
      final counting = _FakeAdapter()
        ..answers['wit/wiql/$queryId'] = {
          'workItemRelations': [
            {
              'target': {'id': 15545},
            },
          ],
        };
      counting.status = 200;
      // A HEAD that 405s and a GET that works: run them through one adapter
      // by flipping the status after the first request.
      final dio = Dio()
        ..httpClientAdapter = _SwitchingAdapter(
          onFirst: () {
            head = false;
          },
          inner: counting,
          firstStatus: 405,
          isFirst: () => head,
        );
      final repo = WorkItemRepository(
        AdoClient(
          tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
          dio: dio,
        ),
        db,
        userId: account,
      );

      expect(await repo.queryCount(org, project, queryId), 1);
      expect(counting.requests.map((r) => r.method), ['HEAD', 'GET']);
    });

    test('a tree query counts its relation targets', () async {
      adapter.answers['wit/wiql/$queryId'] = {
        'workItemRelations': [
          {
            'target': {'id': 1},
          },
          {
            'target': {'id': 2},
          },
          // A duplicate target is one work item.
          {
            'target': {'id': 2},
          },
        ],
      };
      expect(await repository.queryCount(org, project, queryId), 2);
    });
  });

  group('PipelineRepository.runs queryOrder', () {
    test('defaults to the queue order the Runs tab uses', () async {
      final pipelines = PipelineRepository(client, db, account);
      await pipelines.runs(org, project);
      expect(
        adapter.last.uri.queryParameters['queryOrder'],
        'queueTimeDescending',
      );
    });

    test('the Build History widget asks for finish order', () async {
      final pipelines = PipelineRepository(client, db, account);
      await pipelines.runs(
        org,
        project,
        definitionId: 139,
        top: 20,
        cache: false,
        queryOrder: PipelineRepository.finishTimeDescending,
      );
      final query = adapter.last.uri.queryParameters;
      expect(query['queryOrder'], 'finishTimeDescending');
      expect(query['definitions'], '139');
      expect(query[r'$top'], '20');
    });
  });

  group('pull request link/unlink (research/22 §1)', () {
    const projectGuid = '98720989-0195-48cb-ae2e-0e58ec1bb9a9';
    const repoGuid = '4c06881a-4e20-49c8-88c4-a21323fe04b5';
    const prId = 8401;
    const artifact =
        'vstfs:///Git/PullRequestId/$projectGuid%2F$repoGuid%2F$prId';

    Map<String, dynamic> item({List<Map<String, dynamic>>? relations}) => {
      'id': 15545,
      'rev': 34,
      'fields': {'System.Title': 'Scratch work item'},
      'relations': relations ?? const <Map<String, dynamic>>[],
    };

    Map<String, dynamic> artifactLink(String url) => {
      'rel': 'ArtifactLink',
      'url': url,
      'attributes': {'name': 'Pull Request'},
    };

    List<Map<String, dynamic>> ops(RequestOptions r) => [
      for (final op in r.data as List) (op as Map).cast<String, dynamic>(),
    ];

    test('link adds one ArtifactLink with the encoded separators', () async {
      adapter.answers['wit/workitems/15545'] = item();

      await repository.linkPullRequest(
        org,
        15545,
        projectGuid,
        repoGuid,
        prId,
        project: project,
      );

      // A read with the relations, then the guarded patch.
      expect(adapter.requests.first.method, 'GET');
      expect(adapter.last.method, 'PATCH');
      expect(
        adapter.last.headers[Headers.contentTypeHeader],
        contains('json-patch'),
      );
      final patch = ops(adapter.last);
      // Every work item patch opens with the revision guard.
      expect(patch.first, {'op': 'test', 'path': '/rev', 'value': 34});
      expect(patch.last['op'], 'add');
      expect(patch.last['path'], '/relations/-');
      final value = (patch.last['value'] as Map).cast<String, dynamic>();
      expect(value['rel'], 'ArtifactLink');
      expect(value['url'], artifact);
      // The service stores `%2f`; a plain `/` url is taken as a second,
      // duplicate relation, so the app always writes the encoded form.
      expect(value['url'], contains('%2F'));
      expect(
        value['url'].toString().split('PullRequestId/').last,
        isNot(contains('/')),
      );
      expect((value['attributes'] as Map)['name'], 'Pull Request');
    });

    test('link is a no-op when the relation is already there', () async {
      adapter.answers['wit/workitems/15545'] = item(
        relations: [artifactLink(artifact)],
      );

      await repository.linkPullRequest(
        org,
        15545,
        projectGuid,
        repoGuid,
        prId,
        project: project,
      );

      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('unlink removes the relation by index', () async {
      adapter.answers['wit/workitems/15545'] = item(
        relations: [
          {'rel': 'System.LinkTypes.Hierarchy-Reverse', 'url': 'x'},
          artifactLink(artifact),
        ],
      );

      await repository.unlinkPullRequest(
        org,
        15545,
        projectGuid,
        repoGuid,
        prId,
        project: project,
      );

      final patch = ops(adapter.last);
      expect(patch.first, {'op': 'test', 'path': '/rev', 'value': 34});
      expect(patch.last, {'op': 'remove', 'path': '/relations/1'});
    });

    test('unlink matches the plain-slash and upper-case forms too', () async {
      adapter.answers['wit/workitems/15545'] = item(
        relations: [
          artifactLink(
            'vstfs:///Git/PullRequestId/'
            '${projectGuid.toUpperCase()}/$repoGuid/$prId',
          ),
        ],
      );

      await repository.unlinkPullRequest(
        org,
        15545,
        projectGuid,
        repoGuid,
        prId,
        project: project,
      );

      expect(ops(adapter.last).last, {'op': 'remove', 'path': '/relations/0'});
    });

    test('unlink does nothing when the link has already gone', () async {
      adapter.answers['wit/workitems/15545'] = item();

      await repository.unlinkPullRequest(
        org,
        15545,
        projectGuid,
        repoGuid,
        prId,
        project: project,
      );

      expect(adapter.requests.map((r) => r.method), ['GET']);
    });

    test('the artifact url is built the way the service stores it', () {
      expect(
        WorkItemRepository.pullRequestArtifactUrl(projectGuid, repoGuid, prId),
        artifact,
      );
    });
  });
}

/// Answers the first request with [firstStatus] and everything after it
/// through [inner], so one test can exercise "HEAD refused, GET works".
class _SwitchingAdapter implements HttpClientAdapter {
  _SwitchingAdapter({
    required this.inner,
    required this.firstStatus,
    required this.isFirst,
    required this.onFirst,
  });

  final _FakeAdapter inner;
  final int firstStatus;
  final bool Function() isFirst;
  final void Function() onFirst;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (isFirst()) {
      onFirst();
      inner.requests.add(options);
      return ResponseBody.fromString(
        '',
        firstStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
